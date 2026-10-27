# Runs on windows-latest via GitHub Actions. Exercises the actual app function
# without launching the Windows Forms interface.
$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexResumeScheduler.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors) { throw ($errors.Message -join '; ') }
$function = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Find-SessionRepository' }, $true))
if ($function.Count -ne 1) { throw 'Expected exactly one session repository selector.' }
Invoke-Expression $function[0].Extent.Text

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

    $session.Cwd = 'C:\home'
    $found = Find-SessionRepository $session
    if ($found.Root -ne 'C:/actual') { throw 'A unique recent worktree should be detected.' }

    $previous = @{ sessionId = $session.Id; repo = 'C:/original' } | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $appDir 'CodexResume-prior.json') -Value $previous
    $found = Find-SessionRepository $session
    if ($null -ne $found.Root -or $found.Candidates.Count -ne 2) { throw 'Prior schedules must not hide conflicting current checkout evidence.' }
    Write-Host 'Repository detection checks passed.'
} finally {
    Remove-Item -LiteralPath $appDir -Recurse -Force
}
