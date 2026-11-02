@{
    RootModule = 'GitRepository.psm1'
    ModuleVersion = '1.0.0'
    GUID = '2f3e55f5-4fdc-4a86-b88f-26a9b20abc33'
    Author = 'Codex Resume Scheduler contributors'
    Description = 'Reusable read-only Git repository root and branch inspection.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-GitRepositoryRoot','Get-GitCurrentBranch')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
