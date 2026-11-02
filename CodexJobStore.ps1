# Codex-specific on-disk task and outcome readers. No GUI or worker globals.
Import-Module (Join-Path $PSScriptRoot 'components/JobOutcomes/JobOutcomes.psm1') -ErrorAction Stop
function Get-CodexJobPayloadFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory)
    if(-not (Test-Path -LiteralPath $Directory -PathType Container)){return}
    # Filter *before* any ordering or selection: .result.json is a result,
    # not a saved task. Never discard valid older jobs due to arbitrary "top 5".
    Get-ChildItem -LiteralPath $Directory -Filter 'CodexResume-*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '\.result\.json$' } |
        Sort-Object LastWriteTime -Descending
}
function Get-CodexRunHistory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,[ValidateRange(1,1000)][int]$Limit=50)
    if(-not (Test-Path -LiteralPath $Directory -PathType Container)){return}
    $paths=Get-ChildItem -LiteralPath $Directory -Filter 'CodexResume-*.result.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First $Limit
    foreach($file in $paths){
        $name=$file.Name.Substring(0,$file.Name.Length - '.result.json'.Length)
        $state=Read-JobOutcome -Path $file.FullName
        if(-not $state){
            [pscustomobject]@{Name=$name;When=$file.LastWriteTime;Status='unreadable';Attempt=$null;ExitCode=$null;Message='Result file invalid or unreadable';NextJob=''}
            continue
        }
        $when=$file.LastWriteTime
        try {$when=[DateTimeOffset]::Parse([string]$state.at).LocalDateTime} catch {}
        [pscustomobject]@{
            Name=$name;When=$when;Status=[string]$state.status;Attempt=[int]$state.attempt
            ExitCode=$state.exitCode;Message=[string]$state.message;NextJob=[string]$state.nextJob
        }
    }
}
