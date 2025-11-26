function Invoke-DatabaseBackup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SqlInstance,

        [Parameter(Mandatory)]
        [string]$BackupRoot,

        [Parameter()]
        [string[]]$DatabaseFilter = @(),

        [Parameter()]
        [string]$ReportDirectory = "C:\DBA\Reports",

        [Parameter()]
        [string]$LogoUrl = "file:///E:/TOOLS/HADES/IMAGES.png"
    )

    if (-not (Get-Module -ListAvailable -Name dbatools)) {
        Write-Host "🔧 Installing dbatools module..." -ForegroundColor Yellow
        try {
            Install-Module -Name dbatools -Scope CurrentUser -Force -AllowClobber
            Write-Host "✅ dbatools installed." -ForegroundColor Green
        } catch {
            Write-Host "❌ Failed installing dbatools: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }

    Import-Module dbatools
    Set-DbatoolsInsecureConnection -SessionOnly

    function Convert-Size($bytes) {
        if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
        if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
        if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
        return "$bytes bytes"
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmm"
    if (-not (Test-Path $ReportDirectory)) {
        New-Item -Path $ReportDirectory -ItemType Directory -Force | Out-Null
    }
    $reportPath = Join-Path $ReportDirectory "${SqlInstance}_BackupReport_${timestamp}.html"

    $report = @()
    $databases = Get-DbaDatabase -SqlInstance $SqlInstance |
        Where-Object {
            -not $_.IsSystemObject -and $_.Status -eq 'Normal' -and $_.IsAccessible -and (
                $DatabaseFilter.Count -eq 0 -or $DatabaseFilter -contains $_.Name
            )
        }

    foreach ($db in $databases) {
        $start = Get-Date
        $dbFolder = Join-Path $BackupRoot $db.Name
        if (-not (Test-Path $dbFolder)) {
            New-Item -ItemType Directory -Path $dbFolder -Force | Out-Null
        }

        $stamp    = $start.ToString('yyyyMMdd_HHmmss')
        $filePath = Join-Path $dbFolder ("{0}_COPYONLY_FULL_{1}.bak" -f $db.Name, $stamp)

        Write-Host "`n🔄 Backing up [$($db.Name)] ..." -ForegroundColor Cyan
        try {
            Backup-DbaDatabase -SqlInstance $SqlInstance -Database $db.Name -Type Full -CopyOnly `
                -CompressBackup -Checksum -FilePath $filePath -Initialize | Out-Null

            if (-not (Test-Path $filePath)) {
                throw "Backup file not found"
            }

            $sizeBytes = (Get-Item $filePath).Length
            $sizeFmt = Convert-Size $sizeBytes
            $fileList = Invoke-DbaQuery -SqlInstance $SqlInstance `
                -Query "RESTORE FILELISTONLY FROM DISK = N'$filePath';" |
                ForEach-Object { "$($_.LogicalName) (" + (Convert-Size $_.Size) + ")" }
            $duration = (Get-Date) - $start

            Write-Host "✅ Backup succeeded in $($duration.TotalSeconds)s" -ForegroundColor Green
            $report += [PSCustomObject]@{
                Instance = $SqlInstance
                Database = $db.Name
                Size     = $sizeFmt
                FilePath = $filePath
                FileList = $fileList
                Duration = $duration.ToString("hh\:mm\:ss")
                Status   = "Success"
                Message  = "Backup completed successfully in $($duration.TotalSeconds) seconds."
            }
        } catch {
            Write-Host "❌ Backup failed for [$($db.Name)]: $_" -ForegroundColor Red
            $report += [PSCustomObject]@{
                Instance = $SqlInstance
                Database = $db.Name
                Size     = "Error"
                FilePath = "N/A"
                FileList = @()
                Duration = "00:00:00"
                Status   = "Error"
                Message  = $_.Exception.Message
            }
        }
    }

    # ===================== HTML Report =====================
    $timestampHuman = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    $style = @"
<style>
  body { font-family: Arial, sans-serif; margin:20px; background:#f5f6fa; color:#2e2e2e; }
  .header { display:flex; align-items:center; gap:20px; margin-bottom:20px; }
  .subheader { color:#666; margin-top:4px; }
  table { width:100%; border-collapse:collapse; }
  th, td { padding:10px; border:1px solid #ccc; vertical-align:top; }
  th { background:#e1e5ea; }
  td.center { text-align: center; vertical-align: middle; }
  .toggle-btn { cursor:pointer; border:none; border-radius:4px; padding:4px 10px; font-weight:bold; }
  .success-btn { background:#81c784; color:#fff; }
  .error-btn   { background:#e57373; color:#fff; }
  .file-btn    { background:#0077c8; color:#fff; border:none; border-radius:4px; padding:4px 10px; font-weight:bold; cursor:pointer; }
  .file-details { margin-top:6px; }
  .file-details ul { margin:0; padding-left:20px; }
  .file-details li { margin-bottom:4px; font-family:Consolas, monospace; }
  pre { font-family:Consolas, monospace; margin:0; white-space:pre-wrap; }
</style>
<script>
function toggleNext(btn){
  var el = btn.nextElementSibling;
  if(!el) return;
  el.hidden = !el.hidden;
}
</script>
"@

    $rowsHtml = ""
    foreach ($row in $report) {
        $btnClass = if ($row.Status -eq "Success") { "success-btn" } else { "error-btn" }
        $btnText  = $row.Status
        $fileListHtml = ($row.FileList | ForEach-Object { "<li>$_</li>" }) -join ""
        $rowsHtml += @"
<tr>
  <td>$($row.Instance)</td>
  <td>$($row.Database)</td>
  <td>$($row.Size)</td>
  <td><pre>$($row.FilePath)</pre></td>
  <td class='center'>
    <button class='file-btn' onclick='toggleNext(this)'>Show/Hide</button>
    <div class='file-details' hidden>
      <ul>$fileListHtml</ul>
    </div>
  </td>
  <td>$($row.Duration)</td>
  <td class='center'>
    <button class='toggle-btn $btnClass' onclick='toggleNext(this)'>$btnText</button>
    <div class='file-details' hidden>
      <pre>$($row.Message)</pre>
    </div>
  </td>
</tr>
"@
    }

    $reportHtml = @"
<!DOCTYPE html>
<html lang='en'>
<head><meta charset='UTF-8'><title>Backup Report</title>$style</head>
<body>
  <div class='header'>
    <img src='$LogoUrl' alt='Kaizen Logo' style='height:120px;' />
    <div>
      <h1 style="color:#0077c8; font-size:32px; margin:0;">Backup Summary Report - $SqlInstance</h1>
      <div class='subheader'>Generated at $timestampHuman</div>
    </div>
  </div>
  <table>
    <thead>
      <tr>
        <th>Instance</th><th>Database</th><th>Size</th><th>Backup Path</th><th class='center'>File List</th><th>Duration</th><th class='center'>Details</th>
      </tr>
    </thead>
    <tbody>$rowsHtml</tbody>
  </table>
</body>
</html>
"@

    $reportHtml | Out-File -Encoding UTF8 $reportPath
    Write-Host "`n📄 Report saved to: $reportPath" -ForegroundColor Cyan
}
