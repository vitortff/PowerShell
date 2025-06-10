# Obter todos os serviços relacionados ao SQL Server
$services = Get-Service | Where-Object { $_.DisplayName -like "*SQL Server*" -or $_.Name -like "MSSQL*" }

foreach ($service in $services) {
    if ($service.Status -ne "Running") {
        Write-Host "Iniciando serviço: $($service.Name) - $($service.DisplayName)"
        Start-Service -Name $service.Name
    } else {
        Write-Host "Serviço já em execução: $($service.Name)"
    }
}
