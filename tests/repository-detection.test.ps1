# Runs on windows-latest via GitHub Actions. Exercises the actual app function
# without launching the Windows Forms interface.
$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexData.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors) { throw ($errors.Message -join '; ') }
$function = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Find-SessionRepository' }, $true))
if ($function.Count -ne 1) { throw 'Expected exactly one session repository selector.' }
Invoke-Expression $function[0].Extent.Text
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexJobStore.ps1')

$script:roots = @{ 'C:\original' = 'C:/original'; 'C:\actual' = 'C:/actual'; 'C:/original' = 'C:/original' }
function Get-RepositoryRoot {
    param([string]$Path)
    if ($script:roots.ContainsKey($Path)) { return $script:roots[$Path] }
    return $null
}
$appDir = Join-Path ([IO.Path]::GetTempPath()) ('codex-repository-detection-' + [guid]::NewGuid().ToString('N'))
New-Item -Path $appDir -ItemType Directory | Out-Null
try {
    $rollout = Join-Path $appDir 'rollout.jsonl'
    Set-Content -LiteralPath $rollout -Value ''
    $session = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000001'; Cwd = 'C:\original'; File = $rollout }
    $found = Find-SessionRepository $session
    if ($found.Root -ne 'C:/original') { throw 'Unique startup root should be selected.' }

    $arguments = @{ workdir = 'C:\actual' } | ConvertTo-Json -Compress
    $record = @{ type = 'response_item'; payload = @{ type = 'function_call'; arguments = $arguments } } | ConvertTo-Json -Compress -Depth 8
    Set-Content -LiteralPath $rollout -Value $record
    $found = Find-SessionRepository $session
    if ($null -ne $found.Root -or $found.Candidates.Count -ne 2) { throw 'Different worktrees must not silently select the startup root.' }

    # Codex App Server metadata wins over an unrelated original root; both
    # checkouts remain visible for the operator to select deliberately.
    $found = Find-SessionRepository $session 'C:\actual'
    if ($found.Root -ne 'C:/actual' -or $found.Source -ne 'Codex thread/read') { throw 'Codex reported directory must take precedence.' }
    if (@($found.AlternativeRoots).Count -ne 1 -or $found.AlternativeRoots[0] -ne 'C:/original') { throw 'Competing checkout must be shown, not discarded.' }
    $found = Find-SessionRepository $session 'C:\missing'
    if ($null -ne $found.Root) { throw 'Invalid metadata cwd must fall back to conflict detection.' }

    $session.Cwd = 'C:\home'
    $found = Find-SessionRepository $session
    if ($found.Root -ne 'C:/actual') { throw 'A unique recent worktree should be detected.' }

    $previous = @{ sessionId = $session.Id; repo = 'C:/original' } | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $appDir 'CodexResume-prior.json') -Value $previous
    $found = Find-SessionRepository $session
    if ($null -ne $found.Root -or $found.Candidates.Count -ne 2) { throw 'Prior schedules must not hide conflicting current checkout evidence.' }
    $found = Find-SessionRepository $session 'C:\actual'
    if ($found.Root -ne 'C:/actual' -or $found.AlternativeRoots[0] -ne 'C:/original') { throw 'Previous schedule must not override Codex metadata.' }
    # Outcome records sort newest but are not job payloads. A valid old
    # schedule must not be displaced even after many newer completed runs.
    1..20 | ForEach-Object {
        $outcome=Join-Path $appDir ("CodexResume-noise{0:00}.result.json" -f $_)
        '{"schema":1,"status":"completed","at":"2026-01-01T00:00:00Z","attempt":0,"exitCode":0,"message":"","nextJob":""}' |
            Set-Content -LiteralPath $outcome
    }
    $found = Find-SessionRepository $session
    if ($null -ne $found.Root -or @($found.Candidates).Count -ne 2) {
        throw 'Completed-run result records displaced older valid repository evidence.'
    }
    $payloads=@(Get-CodexJobPayloadFiles -Directory $appDir)
    if ($payloads.Count -ne 1 -or $payloads[0].Name -ne 'CodexResume-prior.json') {
        throw 'Job-file reader included result files or lost older saved jobs.'
    }
    Write-Host 'Repository detection checks passed.'
} finally {
    Remove-Item -LiteralPath $appDir -Recurse -Force
}
