# One explicitly owned application UI context. GUI modules share this context,
# rather than creating unrelated script-scoped globals in each dot-sourced file.
# The reusable components must never import or depend on this file.
function New-CodexUiState {
    param($Settings=$null)
    $state=[pscustomobject]@{
        Selection = @{
            dataJobs=@{}; dataQueued=@{}; loadingSessions=$false
            models=@(); modelCatalogLoaded=$false
            preferredEffort=''; preferredModelId=''; preferredSessionId=''
            preferredSessionModel=''; repoSelectionSessionId=''
            selectionGeneration=0; selectionJobGeneration=0; selectionOriginalModel=''
            startupSavedModelId=''; startupSavedSessionId=''; updatingModels=$false
        }
        Usage = @{
            usageSnapshot=$null; usageRequestedModel=''; usageSnapshotRequestedModel=''
            usageReadFailed=$false; usageProcess=$null; usageStarted=[datetime]::MinValue
            usageRefreshQueued=$false; usageChecked=[datetime]::MinValue
        }
        Preferences = @{
            uiSettings=$null; savedDraft=$null; settingsReady=$false
            settingsTimer=$null; lastAccessPreference='workspace-write'
        }
        Dashboard = @{
            appearanceButton=$null; compactRunDate=$null; compactRunDetails=$null
            compactRunEta=$null; compactRunHeading=$null; compactRunName=$null
            compactRunPanel=$null; compactRunTrack=$null; compactTitleFont=$null
            compactToggle=$null; compactUsageModel=$null; compactUsageStatus=$null
            countdownBlue=$null; countdownTimer=$null; dashboardStandardOnly=@()
            fullTitleFont=$null; pendingSnapshot=@(); pendingIndex=@{}; runBarHosts=$null
        }
    }
    # One constructor owns every initial value; GUI modules do not reset
    # each other's state while the application is starting.
    $state.Preferences.uiSettings=$Settings
    $state.Preferences.savedDraft=if($Settings -and $Settings.draft){$Settings.draft}else{$null}
    $draft=$state.Preferences.savedDraft
    if($draft){
        $state.Selection.preferredSessionId=[string]$draft.sessionId
        $state.Selection.preferredModelId=[string]$draft.model
        $state.Selection.preferredEffort=[string]$draft.effort
    }
    $state.Selection.startupSavedSessionId=$state.Selection.preferredSessionId
    $state.Selection.startupSavedModelId=$state.Selection.preferredModelId
    return $state

}
