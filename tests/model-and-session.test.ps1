$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'CodexRunEngine.ps1'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors){throw ($errors | Out-String)}
foreach ($name in @('Assert-ModelEffortSupported')) {
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
Write-Host 'Model capability checks passed.'
