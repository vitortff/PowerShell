<#
CSV file template
-----------------------------
Instance,LoginName,Password
InstanceName,SQLLogin,LoginPasword
#>


# Parâmetros
$csvFilePath = "E:\DBA\sql_instance_newlogin.csv"  # Caminho para o arquivo CSV com as instâncias, login e senhas

# Importar lista de instâncias, logins e senhas do arquivo CSV
$instances = Import-Csv -Path $csvFilePath

# Iterar sobre cada instância e criar o novo login com permissões sysadmin
foreach ($instance in $instances) {
    $sqlInstance = $instance.Instance
    $newLogin = $instance.LoginName  # Nome do novo login
    $newPassword = $instance.Password  # Senha do novo login

    # Exibir qual instância está sendo processada
    Write-Host "Conectando à instância: $sqlInstance para criar o login '$newLogin'"

    try {
        # Script T-SQL para criar o novo login e conceder permissão sysadmin
        $sqlCommand = "
        IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'$newLogin')
        BEGIN
            CREATE LOGIN [$newLogin] WITH PASSWORD = N'$newPassword', CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF;
            ALTER SERVER ROLE [sysadmin] ADD MEMBER [$newLogin];
        END
        ELSE
        BEGIN
            PRINT 'Login já existe: $newLogin';
        END
        "
        
        # Executar o comando usando autenticação do Windows
        Invoke-Sqlcmd -ServerInstance $sqlInstance -Query $sqlCommand -ErrorAction Stop
        
        # Exibir mensagem de sucesso
        Write-Host "Login '$newLogin' criado e concedida permissão sysadmin na instância: $sqlInstance" -ForegroundColor Green
    }
    catch {
        # Exibir mensagem de erro se a alteração falhar
        Write-Host "Erro ao conectar ou criar o login na instância: $sqlInstance" -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
}