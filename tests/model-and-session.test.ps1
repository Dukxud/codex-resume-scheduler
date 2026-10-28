$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'CodexResumeScheduler.ps1'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors){throw ($errors | Out-String)}
foreach ($name in @('Get-CodexSessionCollision','Get-SavedAccessPreference','Save-AccessPreference','Assert-ModelEffortSupported')) {
    $matches=@($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true))
    if($matches.Count -ne 1){throw "Missing unique function $name"}
    Invoke-Expression $matches[0].Extent.Text
}
function Assert-Equal($Actual,$Expected,[string]$Description) {if($Actual -cne $Expected){throw "$Description expected '$Expected' but got '$Actual'"}}
$id='01a14053-b774-7580-96eb-aafee116d411'; $other='01a14053-b774-7580-96eb-aafee116d412'
$exact=@([pscustomobject]@{Name='codex.exe';CommandLine="codex.exe resume $id"})
Assert-Equal (Get-CodexSessionCollision $id $exact).Status 'matched' 'exact session collision'
Assert-Equal (Get-CodexSessionCollision $id @([pscustomobject]@{Name='codex.exe';CommandLine="codex.exe resume $other"})).Status 'not-detected' 'different explicit session'
Assert-Equal (Get-CodexSessionCollision $id @([pscustomobject]@{Name='codex.exe';CommandLine='codex.exe'})).Status 'possible' 'bare codex'
Assert-Equal (Get-CodexSessionCollision $id @([pscustomobject]@{Name='codex.exe';CommandLine='codex.exe app-server --listen stdio://'})).Status 'not-detected' 'app-server is not interactive session'
Assert-Equal (Get-CodexSessionCollision $id @([pscustomobject]@{Name='node.exe';CommandLine='node.exe C:\codex\bin\codex.js'})).Status 'not-detected' 'unrelated Node script'
Assert-Equal (Get-CodexSessionCollision $id @([pscustomobject]@{Name='node.exe';CommandLine='node.exe C:\node_modules\@openai\codex\bin\codex.js'})).Status 'possible' 'npm codex without explicit id'
$models = @([pscustomobject]@{id='gpt-6.1-sol';efforts=@('low','max')},[pscustomobject]@{id='gpt-6-luna';efforts=@('medium')})
Assert-ModelEffortSupported $models 'gpt-6.1-sol' 'max'
foreach($case in @(@('gpt-6.1-sol','ultra'),@('gpt-6-luna','max'),@('unknown','low'))){
    $rejected=$false
    try {Assert-ModelEffortSupported $models $case[0] $case[1]}catch{$rejected=$true}
    if(-not $rejected){throw "Unsupported pair was allowed: $($case -join '/')"}
}
$appDir=Join-Path ([IO.Path]::GetTempPath()) ('codex-access-preferences-'+[guid]::NewGuid().ToString('N'))
try {
    Assert-Equal (Get-SavedAccessPreference) 'workspace-write' 'default access'
    Save-AccessPreference 'yolo'; Assert-Equal (Get-SavedAccessPreference) 'yolo' 'saved full access'
    Save-AccessPreference 'read-only'; Assert-Equal (Get-SavedAccessPreference) 'read-only' 'saved read-only'
    Set-Content -LiteralPath (Join-Path $appDir 'settings.json') -Value '{"lastAccess":"wrong"}'
    Assert-Equal (Get-SavedAccessPreference) 'workspace-write' 'invalid saved access defaults safely'
} finally {if(Test-Path $appDir){Remove-Item -LiteralPath $appDir -Recurse -Force}}
Write-Host 'Model capabilities, CLI collision, and saved access checks passed.'
