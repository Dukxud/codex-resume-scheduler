# Persist observable job outcomes independently of a host scheduler or CLI.
Import-Module (Join-Path $PSScriptRoot '../SettingsStore/SettingsStore.psm1') -ErrorAction Stop
function Write-JobOutcome {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,
          [Parameter(Mandatory)][ValidateSet('completed','failed','deferred','blocked','cancelled')][string]$Status,
          [int]$Attempt=0,
          [Nullable[int]]$ExitCode=$null,
          [string]$Message='',
          [string]$NextJob='')
    if($Attempt -lt 0){throw 'Attempt number cannot be negative.'}
    $record=[ordered]@{
        schema=1;status=$Status;at=[DateTimeOffset]::UtcNow.ToString('o')
        attempt=$Attempt;exitCode=$ExitCode;message=$Message;nextJob=$NextJob
    }
    SettingsStore\Write-JsonSettings -Path $Path -Value $record
    return [pscustomobject]$record
}
function Read-JobOutcome {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $data=SettingsStore\Read-JsonSettings -Path $Path
    if(-not $data -or $data.schema -ne 1 -or [string]$data.status -notin @('completed','failed','deferred','blocked','cancelled')){return $null}
    return $data
}
Export-ModuleMember -Function Write-JobOutcome,Read-JobOutcome
