# Importa o módulo DBATools (caso ainda não esteja carregado)
Import-Module DBATools

# Caminho para o arquivo CSV
$csvPath = "E:\DBA\SQLServerInstances_Phase7.csv"

# Importa o CSV
$serverList = Import-Csv -Path $csvPath

foreach ($server in $serverList) {
    $source = $server.SourceSQLInstance
    $destination = $server.DestinationSQLInstance

    Write-Host "Iniciando cópia de objetos e configurações de $source para $destination..."

    # Copiar operadores
    Copy-DbaAgentOperator -Source $source -Destination $destination -Force
    Write-Host "Operadores copiados com sucesso."

    # Copiar alertas
    Copy-DbaAgentAlert -Source $source -Destination $destination -Force
    Write-Host "Alertas copiados com sucesso."

    # Copiar credenciais
    Copy-DbaCredential -Source $source -Destination $destination -Force
    Write-Host "Credenciais copiadas com sucesso."

    # Copiar proxies
    Copy-DbaAgentProxy -Source $source -Destination $destination -Force
    Write-Host "Proxies copiados com sucesso."

    # Copiar schedules
    Copy-DbaAgentSchedule -Source $source -Destination $destination -Force
    Write-Host "Schedules copiados com sucesso."

    # Copiar jobs
    Copy-DbaAgentJob -Source $source -Destination $destination -Force
    Write-Host "Jobs copiados com sucesso."

    # Copiar configurações do Database Mail
    Copy-DbaDbMail -Source $source -Destination $destination -Force
    Write-Host "Database Mail (perfis, contas) copiados com sucesso."

    # Sincronizar configurações do sp_configure
    $sourceConfigs = Get-DbaSpConfigure -SqlInstance $source
    $destinationConfigs = Get-DbaSpConfigure -SqlInstance $destination

    foreach ($config in $sourceConfigs) {
        $destConfig = $destinationConfigs | Where-Object { $_.Name -eq $config.Name }
        if ($destConfig -and $config.RunningValue -ne $destConfig.RunningValue) {
            Set-DbaSpConfigure -SqlInstance $destination -Name $config.Name -Value $config.RunningValue -EnableException:$false
            Write-Host "Configuração '$($config.Name)' ajustada para $($config.RunningValue)."
        }
    }

    Write-Host "Configurações do sp_configure sincronizadas com sucesso."

    Write-Host "Todos objetos e configurações copiados de $source para $destination."
}

Write-Host "Processo concluído!"
