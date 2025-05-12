Set-DbatoolsInsecureConnection
# Caminho para o arquivo CSV
$configFilePath = "E:\DBA\SQLServerInstanceList_Test.csv"

# Ler cada linha do CSV e executar o processo de log shipping para cada configuração
Import-Csv -Path $configFilePath | ForEach-Object {

    $SourceInstanceName = ( $_.SourceSqlInstance -split '\\')[1]

    # Desabilitar os jobs específicos no servidor de origem
    #Set-DbaAgentJob -SqlInstance $_.SourceSqlInstance -Job $SourceInstanceName + 'Plan Sat.Subplan_1' -Disabled -Confirm:$false
    #Disable-DbaAgentJob -SqlInstance $_.SourceSqlInstance -Job $SourceInstanceName + 'Plan SunFri.Subplan_1' -Disabled -Confirm:$false

    # Altera o recovery model para FULL
    Set-DbaDbRecoveryModel -SqlInstance $_.SourceSqlInstance -Database "SBMSDATA" -RecoveryModel Full -Confirm:$false

    # Definir os parâmetros para o Invoke-DbaDbLogShipping
    $params = @{
        SourceSqlInstance                   = $_.SourceSqlInstance
        DestinationSqlInstance              = $_.DestinationSqlInstance
        Database                            = "SBMSDATA"
        GenerateFullBackup                  = $true
        SharedPath                          = $_.BackupNetworkPath
        LocalPath                           = $_.BackupLocalPath
        BackupScheduleFrequencySubdayType   = 'Minutes'
        BackupScheduleFrequencySubdayInterval = 15
        CopyDestinationFolder               = $_.CopyDestinationFolder
        CopyScheduleFrequencySubdayType     = 'Minutes'
        CopyScheduleFrequencySubdayInterval = 15
        RestoreScheduleFrequencySubdayType  = 'Minutes'
        RestoreScheduleFrequencySubdayInterval = 15
        CompressBackup                      = $true
        Force                               = $true
    }

    # Executar o comando Invoke-DbaDbLogShipping com os parâmetros
    Invoke-DbaDbLogShipping @params
}
