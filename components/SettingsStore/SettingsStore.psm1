# Single-writer, replaceable JSON preferences only; host chooses path/schema.
# Missing and corrupt JSON both read as null. No revision, concurrency, history
# or database durability guarantees. Never use this for measurement records.
function Read-JsonSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) }
    catch { return $null }
}
function Write-JsonSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,
          [Parameter(Mandatory)]$Value)
    $target = [IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $target
    [void](New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop)
    $temporary = Join-Path $directory ('.settings-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporary -Encoding utf8 -ErrorAction Stop
        [IO.File]::Move($temporary,$target,$true)
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}
Export-ModuleMember -Function Read-JsonSettings,Write-JsonSettings
