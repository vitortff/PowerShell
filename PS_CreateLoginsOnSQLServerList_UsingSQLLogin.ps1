<#
CSV file template
-----------------------------
Instance,Login,Password
InstanceName,SQLLogin,LoginPasword
#>

# Parâmetros
$csvFilePath = "E:\DBA\sql_instances_credentials.csv"  # Caminho para o arquivo CSV com as instâncias, login e senhas

# Script T-SQL que será executado em cada instância
$sqlCommand = @"
USE [master];
GO
CREATE LOGIN [GOTOSTRATA\MSSQL_DBA_Group] FROM WINDOWS WITH DEFAULT_DATABASE=[master];
GO
ALTER SERVER ROLE [sysadmin] ADD MEMBER [GOTOSTRATA\MSSQL_DBA_Group];
GO
"@

# Importar lista de instâncias, logins e senhas do arquivo CSV
$instances = Import-Csv -Path $csvFilePath

# Iterar sobre cada instância e executar o script T-SQL
foreach ($instance in $instances) {
    $sqlInstance = $instance.Instance
    $login = $instance.Login       # Login para autenticação
    $password = $instance.Password  # Senha para autenticação

    # Exibir qual instância está sendo processada
    Write-Host "Conectando à instância: $sqlInstance com o login '$login'"

    try {
        # Executar o comando T-SQL na instância especificada
        Invoke-Sqlcmd -ServerInstance $sqlInstance -Username $login -Password $password -Query $sqlCommand -ErrorAction Stop
        
        # Exibir mensagem de sucesso
        Write-Host "Script executado com sucesso na instância: $sqlInstance" -ForegroundColor Green
    }
    catch {
        # Exibir mensagem de erro se a conexão ou execução falhar
        Write-Host "Erro ao conectar ou executar o script na instância: $sqlInstance" -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
}