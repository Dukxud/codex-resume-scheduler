# Pure countdown formatting and elapsed fraction. Independent of Windows Forms.
function Get-CountdownText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][datetime]$DueAt,[Parameter(Mandatory)][datetime]$Now)
    $seconds = [long][math]::Ceiling(($DueAt - $Now).TotalSeconds)
    if ($seconds -le 0) { return 'Due now' }
    $days = [long][math]::Floor($seconds / 86400)
    $hours = [long][math]::Floor(($seconds % 86400) / 3600)
    $minutes = [long][math]::Floor(($seconds % 3600) / 60)
    $remainder = $seconds % 60
    if ($days) { return ('{0}d {1}h {2}m' -f $days,$hours,$minutes) }
    if ($hours) { return ('{0}h {1}m' -f $hours,$minutes) }
    if ($minutes) { return ('{0}m {1}s' -f $minutes,$remainder) }
    return ('{0}s' -f $remainder)
}
function Get-CountdownElapsedPercent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][datetime]$DueAt, $CreatedAt,
          [Parameter(Mandatory)][datetime]$Now)
    if ($null -eq $CreatedAt -or [string]$CreatedAt -notmatch '^\d{9,12}$') { return $null }
    try {
        $start = [DateTimeOffset]::FromUnixTimeSeconds([long]$CreatedAt).LocalDateTime
        $duration = ($DueAt - $start).TotalSeconds
        if ($duration -le 0) { return $null }
        return [int][math]::Round([math]::Clamp(100 * ($Now-$start).TotalSeconds / $duration, 0, 100))
    } catch { return $null }
}
Export-ModuleMember -Function Get-CountdownText,Get-CountdownElapsedPercent
