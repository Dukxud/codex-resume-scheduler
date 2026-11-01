# Verify that appearance controls actually open, save, restore and cancel.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexData.ps1')
. (Join-Path $root 'CodexFlowingBar.ps1')
. (Join-Path $root 'CodexAeroBar.ps1')
. (Join-Path $root 'CodexBarAppearance.ps1')
function Require($ok,[string]$message) { if (-not $ok) { throw $message } }

$script:saves = 0
function Queue-FormStateSave { $script:saves++ }

$owner = [System.Windows.Forms.Form]::new()
$owner.ClientSize = [System.Drawing.Size]::new(480,150)
$owner.StartPosition = 'Manual'
$owner.Show()

$timer = [System.Windows.Forms.Timer]::new()
$timer.Interval = 120
$script:attempts = 0
$timer.Add_Tick({
    $script:attempts++
    if ($script:attempts -gt 30) {
        $timer.Stop()
        foreach ($window in @([System.Windows.Forms.Application]::OpenForms)) {
            if ($window.Text -eq 'Customize progress bars') { $window.Close() }
        }
        throw 'Appearance dialog did not expose its controls.'
    }
    $dialog = @([System.Windows.Forms.Application]::OpenForms | Where-Object {
        $_.Text -eq 'Customize progress bars'
    }) | Select-Object -First 1
    if (-not $dialog) { return }

    $combos = @($dialog.Controls | Where-Object { $_ -is [System.Windows.Forms.ComboBox] })
    $sliders = @($dialog.Controls | Where-Object { $_ -is [System.Windows.Forms.TrackBar] })
    $checkboxes = @($dialog.Controls | Where-Object { $_ -is [System.Windows.Forms.CheckBox] })
    Require ($combos.Count -eq 4 -and $sliders.Count -eq 2 -and $checkboxes.Count -eq 1) 'Appearance choices missing.'
    $previewPanel = @($dialog.Controls | Where-Object { $_.Name -eq 'LiveAeroPreview' }) | Select-Object -First 1
    Require ($null -ne $previewPanel) 'Real-time preview container is missing.'
    $previewBars = @($previewPanel.Controls | Where-Object { $_.Tag -and $_.Tag.Kind })
    Require ($previewBars.Count -eq 2) 'Both live preview renderers must exist.'
    $chooserButtons = @($dialog.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq 'Choose...' })
    Require ($chooserButtons.Count -eq 2) 'Both Windows custom color pickers must be present.'
    Require ($combos[0].DrawMode -eq 'OwnerDrawFixed' -and $combos[1].DrawMode -eq 'OwnerDrawFixed') 'Color samples must be drawn.'
    $combos[0].SelectedIndex = 2 # cyan quota
    $combos[1].SelectedIndex = 3 # violet countdown
    $combos[2].SelectedIndex = 2 # pearl
    $combos[3].SelectedIndex = 1 # daylight
    $sliders[0].Value = 145
    $sliders[1].Value = 190
    $checkboxes[0].Checked = $false
    # The real WinForms/WebView2 bars change BEFORE Save is pressed.
    Require ($script:aeroAppearance['quota'] -eq 'cyan' -and $script:aeroAppearance['time'] -eq 'violet') 'Color selection did not preview immediately.'
    Require ($script:aeroAppearance['shimmer'] -eq 145 -and $script:aeroAppearance['speed'] -eq 190) 'Shimmer controls did not preview immediately.'
    Require ($previewBars[0].Tag.Color -eq 'cyan' -and $previewBars[1].Tag.Color -eq 'violet') 'Live preview colors did not change.'
    Require ($script:saves -eq 0) 'Draft appearance changes must not persist until Save.'
    $save = @($dialog.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq 'Save and close' }) | Select-Object -First 1
    Require ($null -ne $save) 'Save and close button missing.'
    $timer.Stop()
    $save.PerformClick()
})
try {
    $timer.Start()
    Show-AeroAppearanceDialog $owner
    Require ($script:aeroAppearance['quota'] -eq 'cyan') 'Chosen quota color was not applied.'
    Require ($script:aeroAppearance['time'] -eq 'violet') 'Chosen countdown color was not applied.'
    Require ($script:aeroAppearance['finish'] -eq 2 -and $script:aeroAppearance['lighting'] -eq 1) 'Material or studio not saved.'
    Require ($script:aeroAppearance['shimmer'] -eq 145 -and $script:aeroAppearance['speed'] -eq 190) 'Shimmer controls not saved.'
    Require (-not $script:aeroAppearance['aero']) 'Aero switch not saved.'
    Require ($script:saves -eq 1) 'Appearance should request one settings save.'

    $folder = Join-Path ([IO.Path]::GetTempPath()) ('codex-bar-preferences-' + [guid]::NewGuid().ToString('N'))
    try {
        Write-CodexUiSettings $folder ([pscustomobject]@{version=1;compactMode=$true;barAppearance=$script:aeroAppearance})
        $loaded = Read-CodexUiSettings $folder
        Initialize-AeroAppearance $loaded
        Require ($script:aeroAppearance['quota'] -eq 'cyan' -and $script:aeroAppearance['speed'] -eq 190) 'Preferences failed to survive reload.'
        Require (-not $script:aeroAppearance['aero']) 'Disabled state failed to survive reload.'
    } finally {
        Remove-Item $folder -Force -Recurse -ErrorAction SilentlyContinue
    }
    # Cancel must roll back live edits rather than saving them or leaving
    # modified colors on the open scheduler.
    $script:attempts = 0
    $timer.Add_Tick({
        $dialog = @([System.Windows.Forms.Application]::OpenForms | Where-Object {
            $_.Text -eq 'Customize progress bars'
        }) | Select-Object -First 1
        if (-not $dialog) { return }
        $combo = @($dialog.Controls | Where-Object { $_ -is [System.Windows.Forms.ComboBox] })[0]
        $combo.SelectedIndex = 0
        Require ($script:aeroAppearance['quota'] -eq 'green') 'Cancel test did not apply live change.'
        $button = @($dialog.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq 'Cancel' }) | Select-Object -First 1
        $timer.Stop()
        $button.PerformClick()
    })
    $timer.Start()
    Show-AeroAppearanceDialog $owner
    Require ($script:aeroAppearance['quota'] -eq 'cyan') 'Cancel did not restore original color.'
    Require ($script:saves -eq 1) 'Cancel unexpectedly saved draft changes.'

    # Arbitrary picker selections survive settings serialization.
    $customAppearance = [ordered]@{quota='#F08030';time='#2AA9E1';finish=2;lighting=1;shimmer=145;speed=190;aero=$true}
    Update-AeroAppearance $customAppearance
    $testFolder = Join-Path ([IO.Path]::GetTempPath()) ('codex-bar-custom-' + [guid]::NewGuid().ToString('N'))
    try {
        Write-CodexUiSettings $testFolder ([pscustomobject]@{version=1;barAppearance=$script:aeroAppearance})
        Initialize-AeroAppearance (Read-CodexUiSettings $testFolder)
        Require ($script:aeroAppearance['quota'] -eq '#F08030' -and $script:aeroAppearance['time'] -eq '#2AA9E1') 'Custom color did not survive restart.'
    } finally { Remove-Item $testFolder -Force -Recurse -ErrorAction SilentlyContinue }
    Write-Host 'Appearance live previews, swatches, custom colors, Cancel and persistence verified.'
} finally {
    $timer.Stop()
    $timer.Dispose()
    $owner.Close()
    $owner.Dispose()
}