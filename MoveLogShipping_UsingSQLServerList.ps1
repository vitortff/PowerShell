Set-DbatoolsInsecureConnection
# Caminho para o arquivo CSV
$configFilePath = "E:\DBA\SQLServerInstances.csv"

# Ler cada linha do CSV e executar o processo de log shipping para cada configuração
Import-Csv -Path $configFilePath | ForEach-Object {

    $SourceInstanceName = ( $_.SourceSqlInstance -split '\\')[1]

    #Habilitando as replicas secundarias como primarias
    Invoke-DbaDbLogShipRecovery -SqlInstance $_.DestinationSqlInstance -Force
    

}
