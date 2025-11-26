<#
Enable-PSRemoting -Force


#Enable WinRM on the servers 

$servers = Get-Content "E:\DBA\SQLServer_OldServers.txt"

foreach ($server in $servers) {
    Invoke-Command -ComputerName $server -ScriptBlock {
        Enable-PSRemoting -Force
        Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value true
        Set-Item WSMan:\localhost\Service\Auth\Basic -Value true
        netsh advfirewall firewall add rule name="WinRM" dir=in action=allow protocol=TCP localport=5985
    }
}
#>

<#
$servers = Get-Content "E:\DBA\SQLServer_OldServers.txt" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

foreach ($server in $servers) {
    Invoke-Command -ComputerName $server -ScriptBlock {
        $folderPath = "G:\Backup\Databases"

        if (Test-Path $folderPath) {
            Write-Host "Concedendo permissão FULL para Everyone em $folderPath em $env:COMPUTERNAME..."

            Start-Process -FilePath "cmd.exe" -ArgumentList "/c icacls `"$folderPath`" /grant Everyone:F /T /C /Q" -Wait -NoNewWindow
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c icacls `"$folderPath`" /inheritance:e /T /C /Q" -Wait -NoNewWindow

            Write-Host "Permissão FULL aplicada com sucesso em $folderPath no servidor $env:COMPUTERNAME"
        } else {
            Write-Host "O caminho $folderPath não foi encontrado em $env:COMPUTERNAME."
        }
    }
}
#>



$servers = Get-Content "E:\DBA\SQLServer_OldServers.txt"

foreach ($server in $servers) {
    Invoke-Command -ComputerName $server -ScriptBlock {
        $path = "G:\Backup\Databases"
        $shareName = "Databases"
        
        # Cria o compartilhamento (se ainda não existir)
        if (!(Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue)) {
            New-SmbShare -Name $shareName -Path $path -FullAccess "Everyone"
            Write-Output "Compartilhamento criado com sucesso em $($env:COMPUTERNAME)"
        } else {
            Write-Output "Compartilhamento já existe em $($env:COMPUTERNAME)"
        }
    }
}
