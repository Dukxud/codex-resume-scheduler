@{
    RootModule = 'AeroProgress.psm1'
    ModuleVersion = '1.0.0'
    GUID = '45771341-9a91-49b9-9435-bc98ba3df296'
    Author = 'Codex Resume Scheduler contributors'
    Description = 'Reusable, local-only Windows Forms progress material using WebView2 and the approved Aero Liquid renderer.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @(
        'Test-AeroProgressColor','Test-AeroProgressSupport',
        'New-AeroProgressView','Set-AeroProgressViewState','Get-AeroProgressViewStatus'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
