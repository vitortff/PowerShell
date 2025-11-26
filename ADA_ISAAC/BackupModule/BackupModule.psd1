@{
    RootModule        = 'BackupModule.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b2c0d5be-57ec-4e2a-94fc-a11b2f9b07e1'
    Author            = 'Vitor Fava'
    CompanyName       = 'Kaizen'
    Description       = 'Function to perform SQL Server database backups and generate an HTML report.'
    FunctionsToExport = @('Invoke-DatabaseBackup')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
    }
    PowerShellVersion = '5.1'
}
