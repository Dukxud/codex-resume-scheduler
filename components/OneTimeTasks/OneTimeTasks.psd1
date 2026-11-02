@{
    RootModule = 'OneTimeTasks.psm1'
    ModuleVersion = '1.0.0'
    GUID = '6182f7bc-d37d-46c7-8a34-642d9898a0ad'
    Author = 'Codex Resume Scheduler contributors'
    Description = 'Reusable, validated one-time Windows Task Scheduler registration and cancellation.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Register-OneTimeTask','Disable-OneTimeTask','Remove-OneTimeTask')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
