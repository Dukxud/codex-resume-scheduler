# Generic, content-addressed runtime snapshots for independently scheduled programs.
# A snapshot prevents a later deployment from silently changing an existing job.
function Get-RuntimeFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,
          [Parameter(Mandatory)][string[]]$RelativeFiles)
    $root = [IO.Path]::GetFullPath($Directory)
    $entries = [Collections.Generic.List[string]]::new()
    foreach ($relative in @($RelativeFiles | Sort-Object -Unique)) {
        $path = $relative.Replace('\','/')
        if (-not $path -or $path -match '(^/|^[A-Za-z]:|(^|/)\.\.(/|$)|(^|/)\.(/|$))') {
            throw "Unsafe runtime-relative path: $relative"
        }
        $full = [IO.Path]::GetFullPath((Join-Path $root $path))
        if (-not $full.StartsWith($root.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar,
                                  [StringComparison]::OrdinalIgnoreCase)) {
            throw "Runtime file outside source directory: $path"
        }
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Runtime file missing: $path" }
        $hash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
        $entries.Add(('{0}:{1}' -f $path,$hash) + [char]10)
    }
    if ($entries.Count -eq 0) { throw 'Runtime file list cannot be empty.' }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($entries -join ''))
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}
function Assert-RuntimeFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,
          [Parameter(Mandatory)][string[]]$RelativeFiles,
          [Parameter(Mandatory)][string]$ExpectedFingerprint)
    if ($ExpectedFingerprint -notmatch '^[0-9a-fA-F]{64}$') { throw 'Invalid expected runtime fingerprint.' }
    $actual = Get-RuntimeFingerprint -Directory $Directory -RelativeFiles $RelativeFiles
    if ($actual -cne $ExpectedFingerprint.ToLowerInvariant()) {
        throw "Scheduled runtime differs from its original snapshot. Expected $ExpectedFingerprint, found $actual."
    }
}
function Publish-ImmutableRuntime {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourceDirectory,
          [Parameter(Mandatory)][string]$DestinationDirectory,
          [Parameter(Mandatory)][string[]]$RelativeFiles)
    $fingerprint = Get-RuntimeFingerprint -Directory $SourceDirectory -RelativeFiles $RelativeFiles
    $destination = [IO.Path]::GetFullPath($DestinationDirectory)
    [void](New-Item -Path $destination -ItemType Directory -Force)
    $target = Join-Path $destination $fingerprint
    if (Test-Path -LiteralPath $target -PathType Container) {
        Assert-RuntimeFingerprint -Directory $target -RelativeFiles $RelativeFiles -ExpectedFingerprint $fingerprint
        return [pscustomobject]@{ Directory=$target; Fingerprint=$fingerprint }
    }
    $staging = Join-Path $destination ('.staging-' + [guid]::NewGuid().ToString('N'))
    try {
        [void](New-Item -Path $staging -ItemType Directory -Force)
        foreach ($relative in @($RelativeFiles | Sort-Object -Unique)) {
            $source = Join-Path $SourceDirectory $relative
            $output = Join-Path $staging $relative
            [void](New-Item -Path (Split-Path -Parent $output) -ItemType Directory -Force)
            Copy-Item -LiteralPath $source -Destination $output -ErrorAction Stop
        }
        Assert-RuntimeFingerprint -Directory $staging -RelativeFiles $RelativeFiles -ExpectedFingerprint $fingerprint
        try { [IO.Directory]::Move($staging,$target) }
        catch {
            if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw }
            Assert-RuntimeFingerprint -Directory $target -RelativeFiles $RelativeFiles -ExpectedFingerprint $fingerprint
        }
    } finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    }
    return [pscustomobject]@{ Directory=$target; Fingerprint=$fingerprint }
}
Export-ModuleMember -Function Get-RuntimeFingerprint,Assert-RuntimeFingerprint,Publish-ImmutableRuntime
