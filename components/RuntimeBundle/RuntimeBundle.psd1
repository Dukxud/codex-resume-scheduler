@{
    RootModule = 'RuntimeBundle.psm1'
    ModuleVersion = '1.0.0'
    GUID = '9d72756b-0bcf-4a79-ae7e-37dd1a640aff'
    Author = 'Codex Resume Scheduler contributors'
    Description = 'Reusable content-addressed immutable snapshots of script runtime dependencies.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-RuntimeFingerprint','Assert-RuntimeFingerprint','Publish-ImmutableRuntime')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
