Set-DbatoolsInsecureConnection
# Caminho para o arquivo CSV
$configFilePath = "E:\DBA\SQLServerInstanceList_Test.csv"

# Ler cada linha do CSV e executar o processo de log shipping para cada configuração
Import-Csv -Path $configFilePath | ForEach-Object {


# Parâmetros das instâncias de SQL Server
$serverInstance1 = $_.SourceSqlInstance  # Nome da primeira instância
$serverInstance2 = $_.DestinationSqlInstance  # Nome da segunda instância
$database = "master"               # Geralmente usamos o banco 'master' para logins

# Query para listar logins (ignorando logins de sistema)
$queryLogins = @"
SELECT name 
FROM sys.server_principals 
WHERE type IN ('S', 'E', 'X')  -- Inclui SQL Logins, Windows Logins e Logins Externos
  AND name NOT LIKE '##%'      -- Exclui logins de sistema
  AND name <> 'sa';            -- Exclui o login 'sa'
"@

# Função para obter logins de uma instância SQL
function Get-SQLLogins {
    param(
        [string]$serverInstance
    )
    try {
        # Executa a query e retorna os logins como um array
        $logins = Invoke-SqlCmd -ServerInstance $serverInstance `
                                -Database $database `
                                -Query $queryLogins `
                                -OutputAs DataTable
        return $logins.Rows | Select-Object -ExpandProperty name
    } catch {
        Write-Host "Erro ao obter logins de $serverInstance : $_" -ForegroundColor Red
        return @()
    }
}

# Retrieve logins from both instances
$loginsInstance1 = Get-SQLLogins -serverInstance $serverInstance1
$loginsInstance2 = Get-SQLLogins -serverInstance $serverInstance2

# Compare logins
Write-Host "`nComparing logins between instances $serverInstance1 and $serverInstance2..."

# Logins present only in Instance 1
$loginsOnlyIn1 = $loginsInstance1 | Where-Object { $_ -notin $loginsInstance2 }
Write-Host "`nLogins present only in $serverInstance1 :" -ForegroundColor Yellow
$loginsOnlyIn1 | ForEach-Object { Write-Host $_ }

# Logins present only in Instance 2
$loginsOnlyIn2 = $loginsInstance2 | Where-Object { $_ -notin $loginsInstance1 }
Write-Host "`nLogins present only in $serverInstance2 :" -ForegroundColor Yellow
$loginsOnlyIn2 | ForEach-Object { Write-Host $_ }

# Logins common to both instances
$commonLogins = $loginsInstance1 | Where-Object { $_ -in $loginsInstance2 }
Write-Host "`nLogins common to both instances:" -ForegroundColor Green
$commonLogins | ForEach-Object { Write-Host $_ }
}