# One explicitly owned application UI context. GUI modules share this context,
# rather than creating unrelated script-scoped globals in each dot-sourced file.
# The reusable components must never import or depend on this file.
function New-CodexUiState {
    return [pscustomobject]@{
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
}
