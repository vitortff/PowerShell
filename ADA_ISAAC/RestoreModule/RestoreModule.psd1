@{
    RootModule        = 'RestoreModule.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'c4d2af3b-1234-4abd-9ef0-abcdef123456'  # gere um GUID novo se quiser
    Author            = 'Vitor Fava'
    CompanyName       = 'Kaizen Gaming'
    Description       = 'Function to perform restore with optional disk space validation and HTML report generation.'
    FunctionsToExport = @('Invoke-DatabaseRestore')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
    }
    PowerShellVersion = '5.1'
}
