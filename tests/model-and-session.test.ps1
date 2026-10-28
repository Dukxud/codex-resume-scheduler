$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'CodexResumeScheduler.ps1'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors){throw ($errors | Out-String)}
foreach ($name in @('Get-SavedAccessPreference','Save-AccessPreference','Assert-ModelEffortSupported')) {
    $matches=@($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true))
    if($matches.Count -ne 1){throw "Missing unique function $name"}
    Invoke-Expression $matches[0].Extent.Text
}
function Assert-Equal($Actual,$Expected,[string]$Description) {if($Actual -cne $Expected){throw "$Description expected '$Expected' but got '$Actual'"}}
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
Write-Host 'Model capabilities and saved access checks passed.'
