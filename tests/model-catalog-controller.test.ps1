# Independent model-selection controller behavior, no live Codex or app launcher.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexUiState.ps1')
. (Join-Path $root 'CodexUiSelection.ps1')
$script:ui=New-CodexUiState
$modelBox=[System.Windows.Forms.ComboBox]::new()
$effortBox=[System.Windows.Forms.ComboBox]::new()
$schedule=[System.Windows.Forms.Button]::new()
try {
    $models=@(
        [pscustomobject]@{id='gpt-test';name='Default';efforts=@('low','high');defaultEffort='high';isDefault=$true},
        [pscustomobject]@{id='other';name='Alternative';efforts=@('low');defaultEffort='low';isDefault=$false}
    )
    $snapshot=[pscustomobject]@{models=$models}
    $script:ui.Selection.preferredModelId='gpt-test'
    $script:ui.Selection.preferredEffort='high'
    Apply-CodexModelCatalog -Snapshot $snapshot
    if((Get-SelectedModel) -ne 'gpt-test' -or $effortBox.SelectedItem -ne 'high' -or -not $schedule.Enabled){
        throw 'Model catalog lost the persisted model and its supported effort.'
    }
    $alternative=@($modelBox.Items | Where-Object Id -eq 'other') | Select-Object -First 1
    $modelBox.SelectedItem=$alternative
    Select-AvailableEfforts
    Apply-CodexModelCatalog -Snapshot $snapshot
    if((Get-SelectedModel) -ne 'other'){throw 'Refreshing a valid catalog must preserve an explicit current model.'}

    # A failed or empty catalog must revoke prior model/effort authority.
    Apply-CodexModelCatalog -Snapshot ([pscustomobject]@{models=@()})
    if($modelBox.Items.Count -ne 0 -or $effortBox.Items.Count -ne 0 -or $schedule.Enabled){
        throw 'Empty catalog left stale model and reasoning selections enabled.'
    }
    if($script:ui.Selection.updatingModels){throw 'Model-update guard remained active after catalog cleared.'}

    Apply-CodexModelCatalog -Snapshot ([pscustomobject]@{models=@([pscustomobject]@{
        id='no-effort';name='No supported effort';efforts=@();defaultEffort=$null;isDefault=$true
    })})
    if($schedule.Enabled){throw 'Model without an advertised effort must not be schedulable.'}
    if($script:ui.Selection.updatingModels){throw 'Model-update guard remained active after a missing-effort selection.'}
    Write-Host 'Isolated model controller: saved choices, live choice, empty catalog and unknown efforts PASS.'
} finally {
    $modelBox.Dispose()
    $effortBox.Dispose()
    $schedule.Dispose()
}
