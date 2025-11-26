# Ensure dbatools is available
if (-not (Get-Module -ListAvailable dbatools)) {
    Install-Module dbatools -Scope CurrentUser -Force
}
Import-Module dbatools -Force

# Fixed variables for testing
$ServersListPath = 'E:\DBA\servers.txt'
$DownloadPath = '\\sqlmbagsbmspr22\Databases'
$LogFile = 'E:\DBA\SqlPatching.log'
$ReportHtml = 'E:\DBA\SqlPatchingReport.html'
$DownloadOnly = $true
$AutoFailover = $false

# Update reference data
Update-DbaBuildReference -Verbose

function Log($msg) { "$((Get-Date).ToString('s')) [INFO] $msg" | Out-File -Append $LogFile }
function Err($msg) { "$((Get-Date).ToString('s')) [ERROR] $msg" | Out-File -Append $LogFile }

$result = @()

foreach ($svr in Get-Content $ServersListPath) {
    Log "=== Starting on $svr ==="
    try {
        $instances = Get-DbaService -ComputerName $svr -Type Engine -Verbose | Where-Object State -eq 'Running'
        foreach ($inst in $instances) {
            $tsStart = Get-Date
            $instName = if ($inst.InstanceName -eq 'MSSQLSERVER') { $svr } else { "$svr\$($inst.InstanceName)" }
            Log "Processing instance $instName"

            $status = [PSCustomObject]@{
                Server        = $svr
                Instance      = $instName
                SQLVersion    = ''
                Edition       = ''
                Action        = ''
                StartTime     = $tsStart.ToString('yyyy-MM-dd HH:mm:ss')
                EndTime       = ''
                Duration      = ''
                BuildCurrent  = ''
                BuildTarget   = ''
                UpdateName    = ''
                KB            = ''
                DownloadLink  = ''
                Alert         = ''
                Details       = ''
            }

            try {
                $conn = Connect-DbaInstance -SqlInstance $instName
                $status.SQLVersion = $conn.GetSqlServerVersionName()
                $prop = Get-DbaInstanceProperty -SqlInstance $instName -InstanceProperty 'Edition' -EnableException
                $status.Edition = $prop.Edition

                $buildInfo = Get-DbaBuild -SqlInstance $instName -Verbose -ErrorAction Stop
                $status.BuildCurrent = $buildInfo.Build
                $test = Test-DbaBuild -SqlInstance $instName -Latest -Verbose

                if ($test.Compliant) {
                    $status.Action = 'UpToDate'
                    $status.Details = "CU$($test.CULevel) already installed"
                } else {
                    $ref = Get-DbaBuildReference -Build $test.BuildTarget -Verbose
                    $kb = $ref.KBLevel
                    $status.BuildTarget = $test.BuildTarget
                    $status.KB = $kb

                    if ($test.CULevel) {
                        $status.UpdateName = "CU$($test.CULevel) (KB$kb)"
                    } elseif ($test.SPLevel) {
                        $status.UpdateName = "SP$($test.SPLevel) (KB$kb)"
                    } else {
                        $status.UpdateName = "KB$kb"
                    }

                    $kbInfo = Get-DbaKbUpdate -Name $kb -Simple
                    $status.DownloadLink = $kbInfo.Link

                    if (-not (Test-Path "$DownloadPath\*KB$kb*.exe")) {
                        Save-DbaKbUpdate -Name $kb -Path $DownloadPath -Verbose -ErrorAction Stop
                        Log "KB$kb downloaded"
                    }

                    if ($DownloadOnly) {
                        $status.Action = 'DownloadedOnly'
                        $status.Alert = 'Medium'
                        $status.Details = "KB$kb downloaded only"
                    } else {
                        Update-DbaInstance -SqlInstance $instName -Path $DownloadPath `
                            -Version "CU$($test.CULevel)" -Restart -Verbose -ErrorAction Stop
                        $status.Action = 'Patched'
                        $status.Alert = 'Low'
                        $status.Details = "KB$kb applied"
                    }
                }

                if (!$test.Compliant -and ($test.BuildBehind -gt 10)) {
                    $status.Alert = 'High'
                }

            } catch {
                $status.Action = 'Error'
                $status.Alert = 'High'
                $status.Details = $_.Exception.Message
                Err "Error on instance $instName : $_"
            }

            $tsEnd = Get-Date
            $status.EndTime = $tsEnd.ToString('yyyy-MM-dd HH:mm:ss')
            $status.Duration = ($tsEnd - $tsStart).ToString("hh\:mm\:ss")
            $result += $status
        }
    } catch {
        Err "General error on server $svr : $_"
    }
}

# HTML report generation
$style = "<style>table{border-collapse:collapse;} td,th{border:1px solid #ccc;padding:6px;} th{background:#eee;}</style>"
$html = "<html><head><title>SQL Server Patching Report</title>$style</head><body>"
$html += "<h2>Patching Summary - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</h2>"
$html += "<table><tr><th>Server</th><th>Instance</th><th>SQL Version</th><th>Edition</th><th>Action</th><th>StartTime</th><th>EndTime</th><th>Duration</th><th>Current Build</th><th>Target Build</th><th>CU/SP (KB)</th><th>Download Link</th><th>Alert</th><th>Details</th></tr>"

foreach ($row in $result) {
    $linkHtml = ''
    if ($row.DownloadLink) {
        $linkHtml = "<a href='$($row.DownloadLink)'>Download</a>"
    }
    $html += "<tr><td>$($row.Server)</td><td>$($row.Instance)</td><td>$($row.SQLVersion)</td><td>$($row.Edition)</td><td>$($row.Action)</td><td>$($row.StartTime)</td><td>$($row.EndTime)</td><td>$($row.Duration)</td><td>$($row.BuildCurrent)</td><td>$($row.BuildTarget)</td><td>$($row.UpdateName)</td><td>$linkHtml</td><td>$($row.Alert)</td><td>$($row.Details)</td></tr>"
}

$html += "</table></body></html>"
$html | Out-File -Encoding UTF8 $ReportHtml

Log "HTML report generated at $ReportHtml"
Log "Process completed"
