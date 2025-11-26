# Garantir dbatools instalado
if (-not (Get-Module -ListAvailable -Name dbatools)) {
    Install-Module dbatools -Scope CurrentUser -Force
}
Import-Module dbatools -Force

# Variáveis de execução
$ServersConfig = 'E:\DBA\servers_test.json'
$LogFile       = 'E:\DBA\SqlPatching.log'
$ReportHtml    = 'E:\DBA\SqlPatchingReport.html'
$DownloadOnly  = $false
$AutoFailover  = $false

Update-DbaBuildReference -Verbose

function Log($msg)  { "$((Get-Date).ToString('s')) [INFO]  $msg" | Out-File -Append $LogFile }
function Err($msg)  { "$((Get-Date).ToString('s')) [ERROR] $msg" | Out-File -Append $LogFile }

$result  = @()
$servers = Get-Content $ServersConfig | ConvertFrom-Json

foreach ($entry in $servers) {
    $svr          = $entry.Server
    $DownloadPath = $entry.DownloadPath
    Log "=== Starting on server $svr with download path '$DownloadPath' ==="

    try {
        $instances = Get-DbaService -ComputerName $svr -Type Engine -Verbose |
                     Where-Object State -eq 'Running'
        foreach ($inst in $instances) {
            $tsStart  = Get-Date
            $instName = if ($inst.InstanceName -eq 'MSSQLSERVER') { $svr }
                        else { "$svr\$($inst.InstanceName)" }
            Log "Processing instance $instName"

            # Teste de conexão
            try {
                Connect-DbaInstance -SqlInstance $instName -TrustServerCertificate | Out-Null
                Log "Connection successful: $instName"
            } catch {
                Err "Connection failed: $instName — $_"
                continue
            }

            $status = [PSCustomObject]@{
                Server             = $svr
                Instance           = $instName
                ServerDownloadPath = $DownloadPath
                SQLVersion         = ''
                Edition            = ''
                Action             = ''
                StartTime          = $tsStart.ToString('yyyy-MM-dd HH:mm:ss')
                EndTime            = ''
                Duration           = ''
                BuildCurrent       = ''
                BuildTarget        = ''
                UpdateName         = ''
                KB                 = ''
                DownloadLink       = ''
                ReleaseDate        = ''
                Alert              = ''
                Details            = ''
            }

            try {
                # Capturar versão e edição
                $prop = Get-DbaInstanceProperty -SqlInstance $instName
                $status.SQLVersion = ($prop | Where-Object Name -eq 'VersionString').Value
                $status.Edition    = ($prop | Where-Object Name -eq 'Edition').Value

                # Obter build atual
                $buildInfo           = Get-DbaBuild -SqlInstance $instName -ErrorAction Stop
                $status.BuildCurrent = $buildInfo.Build

                # Testar build e decidir instalar
                $test = Test-DbaBuild -SqlInstance $instName -Latest -Verbose
                if ($test.Compliant) {
                    $status.Action  = 'UpToDate'
                    $status.Details = "CU $($test.CULevel) already installed"
                } else {
                    $ref = Get-DbaBuildReference -Build $test.BuildTarget
                    $kb  = $ref.KBLevel
                    $status.BuildTarget = $test.BuildTarget
                    $status.KB          = $kb

                    $status.UpdateName = if ($test.CULevel) { "CU $($test.CULevel)" }
                                         elseif ($test.SPLevel) { "SP $($test.SPLevel)" }
                                         else { "KB $kb" }
                    $status.UpdateName += " (KB $kb)"

                    $kbInfo = Get-DbaKbUpdate -Name $kb -Simple
                    $status.DownloadLink = $kbInfo.Link
                    $status.ReleaseDate  = if ($kbInfo.SupportedUntil) {
                                              $kbInfo.SupportedUntil.ToString('yyyy-MM-dd')
                                            } else { '' }

                    if (-not (Test-Path "$DownloadPath\*KB$kb*.exe")) {
                        Save-DbaKbUpdate -Name $kb -Path $DownloadPath -Verbose -ErrorAction Stop
                        Log "KB $kb downloaded to '$DownloadPath'"
                    }

                    if ($DownloadOnly) {
                        $status.Action  = 'DownloadedOnly'
                        $status.Alert   = 'Medium'
                        $status.Details = "KB $kb downloaded only"
                    } else {
                        Update-DbaInstance -SqlInstance $instName `
                                           -Path $DownloadPath `
                                           -Version "CU $($test.CULevel)" `
                                           -Restart -TrustServerCertificate -Verbose -ErrorAction Stop
                        $status.Action = 'Patched'
                        $status.Alert  = 'Low'
                        $status.Details = "KB $kb applied"
                    }

                    if (!$test.Compliant -and ($test.BuildBehind -gt 10)) {
                        $status.Alert = 'High'
                    }
                }
            } catch {
                $status.Action  = 'Error'
                $status.Alert   = 'High'
                $status.Details = $_.Exception.Message
                Err "Error processing $instName : $_"
            }

            $tsEnd          = Get-Date
            $status.EndTime = $tsEnd.ToString('yyyy-MM-dd HH:mm:ss')
            $status.Duration = ($tsEnd - $tsStart).ToString("hh\:mm\:ss")
            $result += $status
        }
    } catch {
        Err "General error on server $svr : $_"
    }
}

# Construir relatório HTML
$style = @"
<style>
table { border-collapse: collapse; font-family: Arial; font-size:12px; }
td, th { border:1px solid #ccc; padding:6px; }
th { background:#eee; }
.high   { background:#f8d7da; color:#721c24; font-weight:bold; }
.medium { background:#fff3cd; color:#856404; font-weight:bold; }
.low    { background:#d4edda; color:#155724; font-weight:bold; }
</style>
"@

$html = "<html><head><title>Patching Report</title>$style</head><body>"
$html += "<h2>Patching Summary - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</h2>"
$html += "<table><tr><th>Server</th><th>Instance</th><th>DownloadPath</th><th>SQL Version</th><th>Edition</th><th>Action</th><th>StartTime</th><th>EndTime</th><th>Duration</th><th>Current Build</th><th>Target Build</th><th>CU/SP (KB)</th><th>Download Link</th><th>Release Date</th><th>Alert</th><th>Details</th></tr>"

foreach ($r in $result) {
    $link = if ($r.DownloadLink) { "<a href='$($r.DownloadLink)'>Download</a>" } else { '' }
    $cls  = switch ($r.Alert) {
        'High'   { 'high' }
        'Medium' { 'medium' }
        'Low'    { 'low' }
        default  { '' }
    }
    $html += "<tr><td>$($r.Server)</td><td>$($r.Instance)</td><td>$($r.ServerDownloadPath)</td><td>$($r.SQLVersion)</td><td>$($r.Edition)</td><td>$($r.Action)</td><td>$($r.StartTime)</td><td>$($r.EndTime)</td><td>$($r.Duration)</td><td>$($r.BuildCurrent)</td><td>$($r.BuildTarget)</td><td>$($r.UpdateName)</td><td>$link</td><td>$($r.ReleaseDate)</td><td class='$cls'>$($r.Alert)</td><td>$($r.Details)</td></tr>"
}

$html += "</table></body></html>"
$html | Out-File -Encoding UTF8 $ReportHtml

Log "HTML report generated at $ReportHtml"
Log "Process completed"
