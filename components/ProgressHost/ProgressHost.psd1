@{
    RootModule = 'ProgressHost.psm1'
    ModuleVersion = '1.0.0'
    GUID = '0e93c644-5727-487d-a5c1-8ce428763ed5'
    Author = 'Codex Resume Scheduler contributors'
    Description = 'Reusable WinForms progress surface recovery, layout and lifecycle.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-ProgressHostSurface','Repair-ProgressHost','Set-ProgressHostLayout','Remove-ProgressHost')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
