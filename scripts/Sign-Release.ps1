# Sign only first-party PowerShell files after all source changes, before hashing.
# Requires a genuine externally trusted publisher certificate; no key material is stored.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BundleDirectory,
      [Parameter(Mandatory)][string]$CertificateThumbprint,
      [Parameter(Mandatory)][string]$TimestampServer)
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Authenticode requires Windows.'}
if($TimestampServer -notmatch '^https?://'){throw 'A timestamp-server URL is required.'}
$thumb=($CertificateThumbprint -replace '\s','').ToUpperInvariant()
if($thumb -notmatch '^[A-F0-9]{40,64}$'){throw 'Invalid certificate thumbprint.'}
$cert=@(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object {$_.Thumbprint -eq $thumb}) | Select-Object -First 1
if(-not $cert){throw 'Matching code-signing certificate with private key not found.'}
if(-not $cert.HasPrivateKey -or $cert.NotAfter -le [DateTime]::Now -or $cert.NotBefore -gt [DateTime]::Now){throw 'Signing certificate not currently valid.'}
if($cert.Subject -eq $cert.Issuer){throw 'Refusing self-signed public release certificate.'}
$files=@(Get-ChildItem -LiteralPath $BundleDirectory -Recurse -File | Where-Object {$_.Extension -in @('.ps1','.psm1','.psd1')})
if(-not $files.Count){throw 'No first-party scripts found to sign.'}
foreach($file in $files){
  $result=Set-AuthenticodeSignature -LiteralPath $file.FullName -Certificate $cert -HashAlgorithm SHA256 -IncludeChain NotRoot -TimestampServer $TimestampServer -ErrorAction Stop
  if($result.Status -ne 'Valid'){throw "Signing failed: $($file.Name) - $($result.Status)"}
  $verify=Get-AuthenticodeSignature -LiteralPath $file.FullName
  if($verify.Status -ne 'Valid' -or $verify.SignerCertificate.Thumbprint -ne $thumb){throw "Signature verification failed: $($file.FullName)"}
}
Write-Host "Verified $($files.Count) trusted Authenticode signatures."
