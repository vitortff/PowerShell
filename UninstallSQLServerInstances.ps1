# Caminho para o setup.exe do SQL Server
$setupPath = "C:\Path\To\setup.exe"  # <-- Substitua pelo caminho real

# Caminho para o arquivo de texto com as instâncias
$instanciaFile = "C:\Caminho\para\instancias.txt"  # Exemplo: instancias.txt com I2, I5, I12...

# Verifica se o arquivo existe
if (-Not (Test-Path $instanciaFile)) {
    Write-Error "Arquivo $instanciaFile não encontrado. Abortando script."
    exit
}

# Lê cada instância do arquivo
Get-Content $instanciaFile | ForEach-Object {
    $instanceName = $_.Trim()
    if ($instanceName -eq "") { return }  # Pula linhas vazias

    # Nome do serviço da instância
    $serviceName = "MSSQL`$$instanceName"

    # Verifica se a instância está instalada (serviço existente)
    $instanceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

    if ($null -ne $instanceExists) {
        Write-Host "`n>>> Desinstalando instância: $instanceName" -ForegroundColor Cyan

        $arguments = "/Q /ACTION=Uninstall /INSTANCENAME=$instanceName /FEATURES=SQL,AS /IACCEPTSQLSERVERLICENSETERMS /SkipRules=RebootRequiredCheck"

        try {
            $process = Start-Process -FilePath $setupPath -ArgumentList $arguments -Wait -PassThru

            if ($process.ExitCode -eq 0) {
                Write-Host "✔ Instância $instanceName desinstalada com sucesso." -ForegroundColor Green
            } else {
                Write-Warning "⚠ Falha ao desinstalar $instanceName. Código de saída: $($process.ExitCode)"
            }
        } catch {
            Write-Error "❌ Exceção ao tentar desinstalar $instanceName: $_"
        }
    } else {
        Write-Warning "Instância $instanceName não encontrada neste servidor. Pulando."
    }
}

Write-Host "`nProcesso de desinstalação concluído. Reinicie o servidor, se necessário." -ForegroundColor Yellow
