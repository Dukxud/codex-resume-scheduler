# Read-only local diagnosis. Never disable antivirus or log user prompts/secrets.
[CmdletBinding()]
param([string]$OutputPath=(Join-Path $env:TEMP 'Codex-Scheduler-Security-Diagnostics.txt'))
$ErrorActionPreference='Continue'
$base=Split-Path -Parent $PSScriptRoot
$lines=[Collections.Generic.List[string]]::new()
$lines.Add("Codex Scheduler security diagnostics UTC: $([DateTime]::UtcNow.ToString('o'))")
$lines.Add("OS: $([Environment]::OSVersion.VersionString)")
$lines.Add("PowerShell: $($PSVersionTable.PSVersion)")
foreach($file in (Get-ChildItem -LiteralPath $base -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {$_.Extension -in @('.ps1','.psm1','.psd1','.vbs','.dll','.exe')} | Sort-Object FullName)){
    $relative=$file.FullName.Substring($base.Length+1)
    $digest=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    $sig=if($file.Extension -in @('.ps1','.psm1','.psd1','.dll','.exe')){
        (Get-AuthenticodeSignature -LiteralPath $file.FullName).Status
    }else{'Not signed'}
    $lines.Add("$relative | SHA256=$digest | Signature=$sig")
}
$start=(Get-Date).AddDays(-7)
try{
  $events=@(Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=$start;Id=1000,1001} -ErrorAction Stop |
     Where-Object {$_.Message -match 'pwsh.exe|wscript.exe|msedgewebview2.exe|Bitdefender'} | Select-Object -First 30)
  foreach($ev in $events){$lines.Add("Application crash: $($ev.TimeCreated.ToString('o')) | EventID=$($ev.Id) | Provider=$($ev.ProviderName)")}
}catch{$lines.Add('Application crash log unavailable.')}
try{
  $detections=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Windows Defender/Operational';StartTime=$start;Id=1116,1117} -ErrorAction Stop | Select-Object -First 15)
  foreach($ev in $detections){$lines.Add("Defender event: $($ev.TimeCreated.ToString('o')) | EventID=$($ev.Id)")}
}catch{$lines.Add('Defender event log unavailable or replaced by another antivirus.')}
[IO.File]::WriteAllLines([IO.Path]::GetFullPath($OutputPath),[string[]]$lines,[Text.UTF8Encoding]::new($false))
Write-Host "Wrote non-sensitive diagnostic report: $OutputPath"
