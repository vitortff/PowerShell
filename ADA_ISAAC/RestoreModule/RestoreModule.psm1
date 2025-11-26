<#
.SYNOPSIS
  Módulo para restaurar bancos com checagem de espaço em discos remotos, baseado somente no backup,
  considerando que o banco não existe ainda no destino.
#>

function Get-RemoteDiskInfo {
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName
    )
    try {
        $drives = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Get-PSDrive -PSProvider FileSystem | Select-Object Name, Free
        }
        return $drives | ForEach-Object {
            [PSCustomObject]@{
                Volume    = "$($_.Name):"
                FreeGB    = [math]::Round($_.Free / 1GB, 2)
            }
        }
    } catch {
        Write-Host "WARN: Falha ao obter disco remoto de $ComputerName : $_" -ForegroundColor Yellow
        return @()
    }
}

function Check-InstanceDB {
    param(
        [Parameter(Mandatory=$true)][string]$Instance,
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][object[]]$CsvRowsForInstance,
        [Parameter(Mandatory=$true)][string]$BackupRoot
    )

    $volumesInfo = @()
    $filesList    = @()

    # pega discos remotos
    $remoteDisk = Get-RemoteDiskInfo -ComputerName $ComputerName

    foreach ($grp in ($CsvRowsForInstance | Group-Object databasename)) {
        $dbName = $grp.Name

        # determinar caminho do .bak mais recente
        $folder = Join-Path $BackupRoot $dbName
        if (-not (Test-Path $folder)) {
            $volumesInfo += [PSCustomObject]@{
                Instance     = $Instance
                Database     = $dbName
                Volume       = ""
                NeededGB     = 0
                AvailableGB  = 0
                MissingGB    = 0
                Message      = "Backup folder não encontrado: $folder"
            }
            continue
        }

        $bakFile = Get-ChildItem $folder -Filter *.bak | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $bakFile) {
            $volumesInfo += [PSCustomObject]@{
                Instance     = $Instance
                Database     = $dbName
                Volume       = ""
                NeededGB     = 0
                AvailableGB  = 0
                MissingGB    = 0
                Message      = "Arquivo .bak não encontrado em $folder"
            }
            continue
        }
        $bakPath = $bakFile.FullName

        # obter logical files do backup
        try {
            $fileListObj = Invoke-DbaQuery -SqlInstance $Instance -Query "RESTORE FILELISTONLY FROM DISK=N'$bakPath'" -EnableException 2>$null
        } catch {
            $volumesInfo += [PSCustomObject]@{
                Instance     = $Instance
                Database     = $dbName
                Volume       = ""
                NeededGB     = 0
                AvailableGB  = 0
                MissingGB    = 0
                Message      = "RESTORE FILELISTONLY falhou para $dbName : $_"
            }
            continue
        }

        foreach ($file in $fileListObj) {
            # mapear logical name para physical path via CSV
            $destRow = $grp.Group | Where-Object {
                ($_.name -replace '\s','').Trim().ToLower() -eq ($file.LogicalName -replace '\s','').Trim().ToLower()
            }
            if (-not $destRow) {
                $volumesInfo += [PSCustomObject]@{
                    Instance     = $Instance
                    Database     = $dbName
                    Volume       = ""
                    NeededGB     = 0
                    AvailableGB  = 0
                    MissingGB    = 0
                    Message      = "Mapping CSV ausente p/ logical file: $($file.LogicalName) no DB $dbName"
                }
                continue
            }

            $destPath = $destRow.physical_name
            $volume   = try { Split-Path $destPath -Qualifier } catch { "UNKNOWN:" }
            if (-not $volume) { $volume = "UNKNOWN:" }
            if ($volume[-1] -ne ':') { $volume = "$volume :" }

            $sizeBytes = [int64]$file.Size
            $neededGB  = [math]::Round(($sizeBytes / 1GB) * 1.15, 2)  # margem de segurança

            $availGB = 0
            $match = $remoteDisk | Where-Object { $_.Volume.Trim().ToUpper() -eq $volume.Trim().ToUpper() }
            if ($match) {
                $availGB = $match.FreeGB
            }

            $missingGB = if ($availGB -lt $neededGB) { [math]::Round($neededGB - $availGB, 2) } else { 0 }

            $volumesInfo += [PSCustomObject]@{
                Instance     = $Instance
                Database     = $dbName
                Volume       = $volume
                NeededGB     = $neededGB
                AvailableGB  = $availGB
                MissingGB    = $missingGB
                Message      = ""
            }

            $filesList += [PSCustomObject]@{
                LogicalName = $file.LogicalName
                FilePath    = $destPath
                SizeGB      = [math]::Round($sizeBytes / 1GB, 2)
                Database    = $dbName
                Instance    = $Instance
            }
        }
    }

    return @{
        Volumes = $volumesInfo
        Files   = $filesList
    }
}

function New-RestoreHtmlReport {
    param(
        [object[]]$Report,
        [object[]]$DiskSummary,
        [string]$Timestamp,
        [string[]]$Instances,
        [string]$Mode,
        [string]$LogoUrl
    )

    $style = @"
<style>
  body { font-family:Arial; background:#f5f5f5; padding:20px; }
  h1, h2, h3 { color:#2c3e50; }
  .tabs button { margin:5px; padding:8px 12px; font-weight:bold; cursor:pointer; border:none; border-radius:4px; }
  .btn-success { background:#27ae60; color:#fff; }
  .btn-error   { background:#c0392b; color:#fff; }
  .btn-file    { background:#2980b9; color:#fff; }
  .hidden-block { display:none; background:#ecf0f1; padding:10px; margin-top:10px; border-radius:6px; }
  table { width:100%; border-collapse:collapse; margin-top:10px; }
  th, td { border:1px solid #bdc3c7; padding:8px; text-align:center; }
  th { background:#34495e; color:#fff; }
</style>
<script>
function toggleBlock(id) {
  var block = document.getElementById(id);
  block.style.display = (block.style.display === 'none') ? 'block' : 'none';
}
</script>
"@

    $html = "<html><head><meta charset='utf-8'><title>Restore Report</title>$style</head><body>"
    $html += "<div style='display:flex;align-items:center;gap:20px'><img src='$LogoUrl' height='100'/><div><h1>Restore Summary Report</h1><p>Generated: $Timestamp</p><p>Mode: $Mode</p></div></div>"

    foreach ($inst in $Instances) {
        $instSafe = ($inst -replace '[^a-zA-Z0-9]', '_')
        $diskInst = $DiskSummary | Where-Object { $_.Instance.Trim().ToLower() -eq $inst.Trim().ToLower() }
        $reportInst = $Report | Where-Object { $_.Instance.Trim().ToLower() -eq $inst.Trim().ToLower() }

        $html += "<h2>Instance: $inst</h2>"
        $html += "<button class='btn-file' onclick=`"toggleBlock('disk_$instSafe')`">Disk Summary</button>"
        $html += "<button class='btn-file' onclick=`"toggleBlock('restore_$instSafe')`">Restore Summary</button>"

        # Disk Summary
        $html += "<div id='disk_$instSafe' class='hidden-block'><h3>Disk Summary</h3><table><tr><th>Volume</th><th>Needed GB</th><th>Available GB</th><th>Missing GB</th></tr>"
        if ($diskInst.Count -gt 0) {
            foreach ($d in $diskInst) {
                $html += "<tr><td>$($d.Volume)</td><td>$([math]::Round($d.NeededGB,2))</td><td>$([math]::Round($d.AvailableGB,2))</td><td>$([math]::Round($d.MissingGB,2))</td></tr>"
            }
        } else {
            $html += "<tr><td colspan='4'>No disk data</td></tr>"
        }
        $html += "</table></div>"

        # Restore Summary
        $html += "<div id='restore_$instSafe' class='hidden-block'><h3>Restore Summary</h3><table><tr><th>Database</th><th>Backup File</th><th>Status</th><th>Details</th></tr>"
        $counter = 0
        foreach ($r in $reportInst) {
            $detailsId = "details_${instSafe}_$counter"
            $btnClass = if ($r.Status -eq "Success") { "btn-success" } else { "btn-error" }
            $html += "<tr><td>$($r.Database)</td><td>$($r.BackupFile)</td><td><button class='btn $btnClass' onclick=`"toggleBlock('$detailsId')`">$($r.Status)</button></td>"
            $html += "<td><div id='$detailsId' class='hidden-block'><pre>$($r.Details)</pre></div></td></tr>"
            $counter++
        }
        if ($reportInst.Count -eq 0) {
            $html += "<tr><td colspan='4'>No restore summary data</td></tr>"
        }
        $html += "</table></div>"
    }

    $html += "</body></html>"
    return $html
}

function Invoke-DatabaseRestore {
    param (
        [string[]]$Instances,
        [string]$BackupRoot,
        [string]$CsvPath,
        [string[]]$DatabaseFilter = @(),
        [string]$ReportDirectory = "E:\TOOLS\HADES\Reports",
        [string]$LogoUrl = "file:///E:/TOOLS/HADES/images.png",
        [ValidateSet("CheckOnly","CheckAndRestore")][string]$Mode = "CheckOnly"
    )

    Import-Module dbatools -ErrorAction Stop
    Set-DbatoolsInsecureConnection -SessionOnly

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $htmlName = "RestoreReport_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".html"
    if (-not (Test-Path $ReportDirectory)) {
        New-Item -ItemType Directory -Path $ReportDirectory | Out-Null
    }
    $htmlPath = Join-Path $ReportDirectory $htmlName

    $csv = Import-Csv $CsvPath
    $report = @()
    $diskSummary = @()

    foreach ($inst in $Instances) {
        $csvRows = $csv | Where-Object { $_.Instance.Trim().ToLower() -eq $inst.Trim().ToLower() }

        if ($csvRows.Count -eq 0) { continue }

        if ($DatabaseFilter.Count -gt 0) {
            $csvRows = $csvRows | Where-Object { $DatabaseFilter -contains $_.databasename }
            if ($csvRows.Count -eq 0) { continue }
        }

        $computerName = ($csvRows | Select-Object -First 1).ComputerName.Trim()

        $check = Check-InstanceDB -Instance $inst -ComputerName $computerName -CsvRowsForInstance $csvRows -BackupRoot $BackupRoot

        foreach ($v in $check.Volumes) {
            $diskSummary += [PSCustomObject]@{
                Instance     = $inst
                Volume       = $v.Volume
                NeededGB     = $v.NeededGB
                AvailableGB  = $v.AvailableGB
                MissingGB    = $v.MissingGB
            }
        }

        foreach ($volGroup in ($check.Volumes | Group-Object Database)) {
            $db = $volGroup.Name
            $missingSum = ($volGroup.Group | Measure-Object -Property MissingGB -Sum).Sum

            $status = if ($missingSum -gt 0) { "Error" } else { "Success" }
            $details = ""
            if ($missingSum -gt 0) {
                $details = "Espaço faltando total: $([math]::Round($missingSum,2)) GB nos volumes correspondentes."
            } elseif ($Mode -eq "CheckOnly") {
                $details = "Espaço de disco verificado. Restore não será executado (modo CheckOnly)."
            } else {
                # aqui o restore real se necessário
                try {
                    $folder = Join-Path $BackupRoot $db
                    $bakFile = Get-ChildItem $folder -Filter *.bak | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if (-not $bakFile) {
                        throw "Arquivo de backup .bak não encontrado para $db"
                    }
                    $fileMap = @{}
                    foreach ($row in ($csvRows | Where-Object { $_.databasename -eq $db })) {
                        $fileMap[$row.name] = $row.physical_name
                    }
                    Restore-DbaDatabase -SqlInstance $inst -Path $bakFile.FullName -DatabaseName $db -FileMapping $fileMap -WithReplace -NoRecovery -ErrorAction Stop | Out-Null
                    $status = "Success"
                    $details = "Restore executado com sucesso."
                } catch {
                    $status = "Error"
                    $details = $_.Exception.Message
                }
            }

            $backupFilePath = "N/A"
            $fld = Join-Path $BackupRoot $db
            if (Test-Path $fld) {
                $b = Get-ChildItem $fld -Filter *.bak | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($b) { $backupFilePath = $b.FullName }
            }

            $report += [PSCustomObject]@{
                Instance   = $inst
                Database   = $db
                BackupFile = $backupFilePath
                Status     = $status
                Details    = $details
            }
        }
    }

    $html = New-RestoreHtmlReport -Report $report -DiskSummary $diskSummary -Timestamp $timestamp -Instances $Instances -Mode $Mode -LogoUrl $LogoUrl
    $html | Out-File -FilePath $htmlPath -Encoding UTF8

    Write-Host "📄 Relatório salvo em: $htmlPath" -ForegroundColor Green
}

Export-ModuleMember -Function Invoke-DatabaseRestore, New-RestoreHtmlReport
