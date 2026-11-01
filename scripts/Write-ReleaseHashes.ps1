# Post-sign manifest; hashes detect corruption but alone cannot prove publisher identity.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BundleDirectory)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($BundleDirectory).TrimEnd('\','/')
$rows=@(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {$_.Name -ne 'SHA256SUMS.txt'} |
 ForEach-Object {
   $relative=$_.FullName.Substring($root.Length+1).Replace('\','/')
   [pscustomobject]@{file=$relative;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant();size=$_.Length}
 } | Sort-Object file)
if(-not $rows.Count){throw 'Empty release bundle.'}
$lines=@($rows | ForEach-Object {"$($_.sha256)  $($_.file)"})
[IO.File]::WriteAllLines((Join-Path $root 'SHA256SUMS.txt'),[string[]]$lines,[Text.UTF8Encoding]::new($false))
Write-Host "Hashed $($rows.Count) release files."
