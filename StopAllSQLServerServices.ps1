# Obter todos os serviços relacionados ao SQL Server
$services = Get-Service | Where-Object { $_.DisplayName -like "*SQL Server*" -or $_.Name -like "MSSQL*" }

foreach ($service in $services) {
    if ($service.Status -eq "Running") {
        Write-Host "Parando serviço: $($service.Name) - $($service.DisplayName)"
        Stop-Service -Name $service.Name -Force
    } else {
        Write-Host "Serviço já parado: $($service.Name)"
    }
}

