############# Setup ##############

# Caminho do CSV com as instâncias
$CsvPath = "E:\DBA\servers.txt"

# Carregar instâncias do arquivo CSV
$SQLInstances = (Import-Csv -Path $CsvPath).Instance

# Conta que receberá as permissões
$DBADashServiceAccount = "gotostrata\vfava16"

###################################

# Escapar colchetes, se existirem
$DBADashServiceAccount = $DBADashServiceAccount.Replace("]","]]")

Write-Host "Instâncias carregadas do CSV:" -ForegroundColor Cyan
$SQLInstances | ForEach-Object { Write-Host " - $_" }

# ------------------------------------------
#  sp_WhoIsActive deploy
# ------------------------------------------

Install-DbaWhoIsActive -SqlInstance $SQLInstances -Database master -Confirm:$false

$GrantSQL = "GRANT EXECUTE ON sp_WhoIsActive TO [$DBADashServiceAccount]"
Invoke-DbaQuery -SqlInstance $SQLInstances -Query $GrantSQL

# ------------------------------------------
#  First Responder Kit (FRK)
# ------------------------------------------

Install-DbaFirstResponderKit -SqlInstance $SQLInstances -Database master -Confirm:$false

$GrantSQL = @"
GRANT EXECUTE ON sp_Blitz TO [$DBADashServiceAccount]
GRANT EXECUTE ON sp_BlitzBackups TO [$DBADashServiceAccount]
GRANT EXECUTE ON sp_BlitzCache TO [$DBADashServiceAccount]
GRANT EXECUTE ON sp_BlitzIndex TO [$DBADashServiceAccount]
GRANT EXECUTE ON sp_BlitzFirst TO [$DBADashServiceAccount]
GRANT EXECUTE ON sp_BlitzLock TO [$DBADashServiceAccount]
GRANT EXECUTE ON sp_BlitzWho TO [$DBADashServiceAccount]

/* Required for sp_Blitz */
GRANT EXECUTE ON sp_AllNightLog TO [$DBADashServiceAccount]
GRANT EXECUTE ON sp_AllNightLog_Setup TO [$DBADashServiceAccount]
GRANT EXECUTE ON sp_BlitzQueryStore TO [$DBADashServiceAccount]
GRANT EXECUTE ON sp_DatabaseRestore TO [$DBADashServiceAccount]
GRANT EXECUTE ON sp_ineachdb TO [$DBADashServiceAccount]
"@

Invoke-DbaQuery -SqlInstance $SQLInstances -Query $GrantSQL

# sys.sql_expression_dependencies (sp_BlitzIndex requirement)
$GrantSQL = "GRANT SELECT ON sys.sql_expression_dependencies TO [$DBADashServiceAccount]"
Get-DbaDatabase -SqlInstance $SQLInstances | Invoke-DbaQuery -Query $GrantSQL

# ------------------------------------------
#  Erik Darling scripts
# ------------------------------------------

Install-DbaDarlingData -SqlInstance $SQLInstances -Database master -Confirm:$false

$GrantSQL = @"
GRANT EXECUTE ON sp_HumanEvents TO [$DBADashServiceAccount]
GRANT EXECUTE ON sp_PressureDetector TO [$DBADashServiceAccount]
GRANT EXECUTE ON sp_QuickieStore TO [$DBADashServiceAccount]
"@
Invoke-DbaQuery -SqlInstance $SQLInstances -Query $GrantSQL

# sp_HealthParser
$HealthParser = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/erikdarlingdata/DarlingData/refs/heads/main/sp_HealthParser/sp_HealthParser.sql").Content
Invoke-DbaQuery -SqlInstance $SQLInstances -Query $HealthParser

$GrantSQL = "GRANT EXECUTE ON sp_HealthParser TO [$DBADashServiceAccount]"
Invoke-DbaQuery -SqlInstance $SQLInstances -Query $GrantSQL

# sp_LogHunter
$LogHunter = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/erikdarlingdata/DarlingData/refs/heads/main/sp_LogHunter/sp_LogHunter.sql").Content
Invoke-DbaQuery -SqlInstance $SQLInstances -Query $LogHunter

# ------------------------------------------
#  Kenneth Fisher scripts
# ------------------------------------------

$sp_SrvPermissions = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sqlstudent144/SQL-Server-Scripts/refs/heads/main/sp_SrvPermissions.sql").Content
Invoke-DbaQuery -SqlInstance $SQLInstances -Query $sp_SrvPermissions

$sp_DBPermissions = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sqlstudent144/SQL-Server-Scripts/refs/heads/main/sp_DBPermissions.sql").Content
Invoke-DbaQuery -SqlInstance $SQLInstances -Query $sp_DBPermissions

$GrantSQL = @"
GRANT EXECUTE ON sp_SrvPermissions TO [$DBADashServiceAccount]
GRANT EXECUTE ON sp_DBPermissions TO [$DBADashServiceAccount]
"@
Invoke-DbaQuery -SqlInstance $SQLInstances -Query $GrantSQL

Write-Host "✔ Deploy concluído com sucesso!" -ForegroundColor Green
