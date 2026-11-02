# Repository inspection without a scheduler, UI or application state.
function Get-GitRepositoryRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }
    try {
        $output = & git -C $Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $output) { return $null }
        return ([string]($output | Select-Object -First 1)).Trim()
    } catch { return $null }
}
function Get-GitCurrentBranch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $root = Get-GitRepositoryRoot -Path $Path
    if (-not $root) { throw 'Cannot identify the Git repository.' }
    $output = & git -C $root branch --show-current 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $output) {
        throw 'Unable to identify a Git branch (detached HEAD is not supported).'
    }
    return ([string]($output | Select-Object -First 1)).Trim()
}
Export-ModuleMember -Function Get-GitRepositoryRoot,Get-GitCurrentBranch
