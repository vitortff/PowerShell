# Garantir dbatools instalado
if (-not (Get-Module -ListAvailable -Name dbatools)) {
    Install-Module dbatools -Scope CurrentUser -Force
}
Import-Module dbatools -Force

# Configurações
$ServersConfig = 'E:\DBA\servers_test.json'
$LogFile       = 'E:\DBA\SqlPatching.log'
$ReportHtml    = 'E:\DBA\SqlPatchingReport.html'
$DownloadOnly  = $true
$AutoFailover  = $false

Update-DbaBuildReference -Verbose

function Log($msg) { "$((Get-Date).ToString('s')) [INFO]  $msg" | Out-File -Append $LogFile }
function Err($msg) { "$((Get-Date).ToString('s')) [ERROR] $msg" | Out-File -Append $LogFile }

$result = @()
$servers = Get-Content $ServersConfig | ConvertFrom-Json

foreach ($entry in $servers) {
    $svr = $entry.Server
    $DownloadPath = $entry.DownloadPath
    Log "=== Starting on server $svr with download path '$DownloadPath' ==="

    try {
        $instances = Get-DbaService -ComputerName $svr -Type Engine -Verbose | Where-Object State -eq 'Running'
    } catch {
        Err "Could not enumerate instances on $svr : $_"
        continue
    }

    foreach ($inst in $instances) {
        $tsStart = Get-Date
        $instName = if ($inst.InstanceName -eq 'MSSQLSERVER') { $svr } else { "$svr\$($inst.InstanceName)" }
        Log "Processing instance $instName"

        try {
            Connect-DbaInstance -SqlInstance $instName -TrustServerCertificate -ErrorAction Stop | Out-Null
            Log "Connection successful: $instName"
        } catch {
            Err "Connection failed: $instName — $_"
            $result += [pscustomobject]@{
                Server    = $svr
                Instance  = $instName
                Action    = 'Error'
                Details   = 'Connection failed'
                StartTime = $tsStart
                EndTime   = (Get-Date)
                Duration  = ((Get-Date) - $tsStart).ToString("hh\:mm\:ss")
            }
            continue
        }

        $status = [ordered]@{
            Server        = $svr
            Instance      = $instName
            DownloadPath  = $DownloadPath
            SQLVersion    = ''
            Edition       = ''
            Action        = ''
            StartTime     = $tsStart
            EndTime       = $null
            Duration      = ''
            BuildCurrent  = ''
            BuildTarget   = ''
            UpdateName    = ''
            KB            = ''
            DownloadLink  = ''
            ReleaseDate   = ''
            Alert         = ''
            Details       = ''
        }

        try {
            $prop = Get-DbaInstanceProperty -SqlInstance $instName
            $status.SQLVersion = ($prop | Where-Object Name -eq 'VersionString').Value
            $status.Edition = ($prop | Where-Object Name -eq 'Edition').Value

            $buildInfo = Test-DbaBuild -SqlInstance $instName -Latest -Verbose
            $ref = Get-DbaBuildReference -Build $buildInfo.BuildTarget

            $status.BuildCurrent = $buildInfo.BuildCurrent
            $status.BuildTarget = $buildInfo.BuildTarget

            if ($buildInfo.Compliant) {
                $status.Action = 'UpToDate'
                $status.Details = "CU $($buildInfo.CULevel) already installed"
            } else {
                $kb = $ref.KBLevel
                $status.KB = $kb

                # Ajuste: use diretamente o valor do CULevel ou SPLevel sem prefixo duplicado
                $cuTag = if ($buildInfo.CULevel) {
                    $buildInfo.CULevel
                } elseif ($buildInfo.SPLevel) {
                    "SP$($buildInfo.SPLevel)"
                } else {
                    "KB$kb"
                }

                $status.UpdateName = "$cuTag (KB $kb)"

                $kbInfo = Get-DbaKbUpdate -Name $kb -Simple
                $status.DownloadLink = $kbInfo.Link
                $status.ReleaseDate = if ($kbInfo.SupportedUntil) {
                    $kbInfo.SupportedUntil.ToString('yyyy-MM-dd')
                }

                if (-not (Test-Path "$DownloadPath\*KB$kb*.exe")) {
                    Save-DbaKbUpdate -Name $kb -Path $DownloadPath -Verbose -ErrorAction Stop
                    Log "KB $kb downloaded"
                }

                if ($DownloadOnly) {
                    $status.Action = 'DownloadedOnly'
                    $status.Alert = 'Medium'
                    $status.Details = "KB $kb downloaded only"
                } else {
                    # DEBUG opcional: Write-Host "DEBUG: cuTag='$cuTag'"
                    Update-DbaInstance `
                      -ComputerName $svr `
                      -InstanceName $inst.InstanceName `
                      -Path $DownloadPath `
                      -Version $cuTag `
                      -Restart -Verbose -ErrorAction Stop

                    $status.Action = 'Patched'
                    $status.Alert = 'Low'
                    $status.Details = "KB $kb applied"

                    if ($AutoFailover) {
                        Invoke-DbaAgFailover -SqlInstance $instName -Verbose
                        Log "AG Failover executed"
                    }
                }

                if ($buildInfo.BuildBehind -gt 10) {
                    $status.Alert = 'High'
                }
            }

        } catch {
            Err "Error processing $instName : $_"
            $status.Action = 'Error'
            $status.Alert = 'High'
            $status.Details = $_.Exception.Message
        }

        $status.EndTime = Get-Date
        $status.Duration = ($status.EndTime - $status.StartTime).ToString("hh\:mm\:ss")
        $result += [pscustomobject]$status
    }
}

# Gerar relatório HTML completo
$style = @"
<style>
table { border-collapse: collapse; font-family: Arial; font-size:12px; }
td, th { padding:6px; border:1px solid #ccc; }
th { background:#eee; }
.high   { background:#f8d7da; color:#721c24; }
.medium { background:#fff3cd; color:#856404; }
.low    { background:#d4edda; color:#155724; }
</style>
"@

$html = "<html><head><title>Patching Report</title>$style</head><body>"
$html += "<h2>Patching Summary – $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</h2>"
$html += "<table><tr><th>Server</th><th>Instance</th><th>DownloadPath</th><th>SQL Version</th><th>Edition</th><th>Action</th><th>StartTime</th><th>EndTime</th><th>Duration</th><th>Current Build</th><th>Target Build</th><th>CU/SP (KB)</th><th>Download Link</th><th>Release Date</th><th>Alert</th><th>Details</th></tr>"

foreach ($r in $result) {
    $link = if ($r.DownloadLink) { "<a href='$($r.DownloadLink)'>Download</a>" } else { '' }
    $cls = switch ($r.Alert) { 'High'{'high'} 'Medium'{'medium'} 'Low'{'low'} default{''} }
    $html += "<tr class='$cls'><td>$($r.Server)</td><td>$($r.Instance)</td><td>$($r.DownloadPath)</td><td>$($r.SQLVersion)</td><td>$($r.Edition)</td><td>$($r.Action)</td><td>$($r.StartTime)</td><td>$($r.EndTime)</td><td>$($r.Duration)</td><td>$($r.BuildCurrent)</td><td>$($r.BuildTarget)</td><td>$($r.UpdateName)</td><td>$link</td><td>$($r.ReleaseDate)</td><td>$($r.Alert)</td><td>$($r.Details)</td></tr>"
}

$html += "</table></body></html>"
$html | Out-File -Encoding UTF8 $ReportHtml

Log "HTML report generated at $ReportHtml"
Log "Process completed"
