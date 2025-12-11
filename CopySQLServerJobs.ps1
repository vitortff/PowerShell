# Importa o módulo DBATools (caso ainda não esteja carregado)
Import-Module DBATools

# Caminho para o arquivo CSV
#$csvPath = "E:\DBA\SQLServerInstances_TV_Batch2.csv"
$csvPath = "E:\DBA\SQLServerInstances_Phase7.csv"


# Importa o CSV
$serverList = Import-Csv -Path $csvPath

foreach ($server in $serverList) {
    $source = $server.SourceSQLInstance
    $destination = $server.DestinationSQLInstance

    Write-Host "Copiando jobs de $source para $destination..."

    # Copia os jobs da instância de origem para a de destino
    Copy-DbaAgentJob -Source $source -Destination $destination -Force

    Write-Host "Jobs copiados com sucesso de $source para $destination."
}

Write-Host "Processo concluído!"
