# Simulate an unrelated Windows program that copies *only* components/.
# A component is reusable only if it works without the Codex UI or worker files.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$temp=Join-Path ([IO.Path]::GetTempPath()) ('unrelated-app-' + [guid]::NewGuid().ToString('N'))
try {
    $app=Join-Path $temp 'UnrelatedDesktopApp'
    [void](New-Item -ItemType Directory -Path $app -Force)
    Copy-Item -LiteralPath (Join-Path $root 'components') -Destination $app -Recurse
    if(Test-Path (Join-Path $app 'CodexRunEngine.ps1')){throw 'Independent application must not contain Codex code.'}
    foreach($name in @('Countdown','SettingsStore','RuntimeBundle','GitRepository','OneTimeTasks','JobOutcomes','WindowShell','ProgressHost','FlowingProgress','AeroProgress')){
        Import-Module (Join-Path $app "components/$name/$name.psd1") -Force -ErrorAction Stop
    }
    function Require($ok,[string]$message){if(-not $ok){throw $message}}
    $settings=Join-Path $app 'prefs.json'
    Write-JsonSettings -Path $settings -Value @{feature='separate application'}
    Require ((Read-JsonSettings -Path $settings).feature -eq 'separate application') 'SettingsStore depends on scheduler context.'
    $outcomes=Join-Path $app 'job-result.json'
    [void](Write-JobOutcome -Path $outcomes -Status 'deferred' -ExitCode 17 -Attempt 2 -Message 'Wait for reset.')
    $outcome=Read-JobOutcome -Path $outcomes
    Require ($outcome.status -eq 'deferred' -and $outcome.exitCode -eq 17) 'Generic job lifecycle not retained.'
    $now=[datetime]'2027-01-01T10:00:00'
    Require ((Get-CountdownText -DueAt $now.AddMinutes(3) -Now $now) -eq '3m 0s') 'Countdown depends on Codex.'
    Require (Test-AeroProgressColor -Color '#1A2B3C') 'Aero module cannot load standalone.'
    Require ((Get-Command Remove-OneTimeTask -Module OneTimeTasks).Name -eq 'Remove-OneTimeTask') 'Task registration API incomplete.'
    $independentRepo=Join-Path $app 'another-repository'
    [void](New-Item -ItemType Directory -Path $independentRepo -Force)
    & git -C $independentRepo init -b isolated --quiet
    Require ($LASTEXITCODE -eq 0) 'Independent Git init failed.'
    $actualRoot=([string](Get-GitRepositoryRoot -Path $independentRepo)).TrimEnd([char[]]@('/','\')).Replace('\','/')
    $expectedRoot=([IO.Path]::GetFullPath($independentRepo)).TrimEnd([char[]]@('/','\')).Replace('\','/')
    Require ($actualRoot -ieq $expectedRoot) "Git root mismatch: actual '$actualRoot' expected '$expectedRoot'."
    Require ((Get-GitCurrentBranch -Path $independentRepo) -eq 'isolated') 'Git branch lookup requires Codex.'
    Require ($null -eq (Get-GitRepositoryRoot -Path $app)) 'Unrelated folder was misclassified as a Git repository.'
    $scripts=Join-Path $app 'scripts'
    [void](New-Item -ItemType Directory -Path $scripts -Force)
    Set-Content -LiteralPath (Join-Path $scripts 'worker.ps1') -Value 'Write-Host example'
    $bundle=Publish-ImmutableRuntime -SourceDirectory $scripts -DestinationDirectory (Join-Path $app 'runs') -RelativeFiles @('worker.ps1')
    Assert-RuntimeFingerprint -Directory $bundle.Directory -RelativeFiles @('worker.ps1') -ExpectedFingerprint $bundle.Fingerprint

    $form=New-DesktopWindow -Title 'Completely Unrelated Application' -Width 440 -Height 180
    try {
        $title=Add-DesktopLabel -Parent $form -Text 'Unrelated' -X 8 -Y 8 -Width 200
        $button=Add-DesktopButton -Parent $form -Text 'Example' -X 8 -Y 36
        Require ($title.Parent -eq $form -and $button.Parent -eq $form) 'Desktop window shell has hidden application dependencies.'
        $gloss=New-FlowingProgressView -Parent $form -X 270 -Y 40 -Width 130 -Height 17 -Colors @{BaseTop='#ED9CFF';BaseBottom='#552099';Track='#ECE8FF';Outline='#CCC2DE'} -AccessibleName 'Unrelated application progress'
        $gloss.Tag='belongs to unrelated consumer'
        Set-FlowingProgressViewState -Bar $gloss -Percent 37.5
        Require ($gloss.Tag -eq 'belongs to unrelated consumer') 'Standalone WPF progress must not claim Control.Tag.'
        Require ((Get-FlowingProgressViewValue -Bar $gloss) -eq 37.5) 'WPF module did not retain its own percentage.'
        Require ($gloss.Child.Value -eq 37.5 -and $gloss.AccessibleName -eq 'Unrelated application progress') 'Standalone WPF animation requires Codex adapter.'
        $primary=[System.Windows.Forms.Panel]::new()
        $primary.Bounds=[System.Drawing.Rectangle]::new(8,80,240,20)
        $primary.Tag='Entirely unrelated application metadata'
        $form.Controls.Add($primary)
        $factory={param($parent,$bounds) return [System.Windows.Forms.Panel]::new()}
        $fallback=Repair-ProgressHost -Primary $primary -Failed $true -FallbackFactory $factory
        Require ($fallback -is [System.Windows.Forms.Control] -and $fallback.Parent -eq $form) 'Fallback creation requires Codex.'
        $target=[System.Drawing.Rectangle]::new(25,90,290,24)
        Set-ProgressHostLayout -Primary $primary -Bounds $target -Visible $true
        Require ($fallback.Bounds -eq $target -and -not $primary.Visible) 'Fallback cannot move independently.'
        Require ((Get-ProgressHostSurface -Primary $primary) -eq $fallback) 'Wrong active progress surface.'
        Require ($primary.Tag -eq 'Entirely unrelated application metadata') 'Generic fallback manager must not claim Tag.'
        Reset-ProgressHostFallback -Primary $primary
        Require ($fallback.IsDisposed -and (Get-ProgressHostSurface -Primary $primary) -eq $primary) 'Reset must release fallback and restore primary.'
        $replacement=Repair-ProgressHost -Primary $primary -Failed $true -FallbackFactory $factory
        Require ($replacement -and $replacement -ne $fallback) 'Recovery after reset must create a fresh control.'
        Remove-ProgressHost -Primary $primary
        Require ($primary.IsDisposed -and $fallback.IsDisposed -and $replacement.IsDisposed) 'Progress control ownership leak.'
    }finally{$form.Dispose()}
    Write-Host 'Independent consumer of ten standalone modules PASS.'
}finally{
    if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
