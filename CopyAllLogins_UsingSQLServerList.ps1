Set-DbatoolsInsecureConnection
# Caminho para o arquivo CSV
$configFilePath = "E:\DBA\SQLServerInstanceList_Test.csv"

# Ler cada linha do CSV e executar o processo de log shipping para cada configuração
Import-Csv -Path $configFilePath | ForEach-Object {

    $SourceInstanceName = ( $_.SourceSqlInstance -split '\\')[1]

    # Alterar o banco de dados padrão de todos os logins para master
    Get-DbaLogin -SqlInstance $_.SourceSqlInstance | ForEach-Object {
    Set-DbaLogin -SqlInstance $_.SourceSqlInstance -Login $_.Name -DefaultDatabase "master" -Confirm:$false
    }

    #Copia os logins da origem para o destino, excluindo os logins ja existentes no destino
    Copy-DbaLogin -Source $_.SourceSqlInstance -Destination $_.DestinationSqlInstance -ExcludeLogin GOTOSTRATA\MBSQLAdminGroup,GOTOSTRATA\MSSQL_DBA_Group, GOTOSTRATA\TechOpsSQLAdminGroup -ExcludeSystemLogins -Force

}
