function Invoke-DatabaseRestore {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$Instances,

        [Parameter(Mandatory=$true)]
        [string]$BackupRoot,

        [Parameter(Mandatory=$true)]
        [string]$CsvPath,

        [Parameter(Mandatory=$true)]
        [pscredential]$SqlCredential,

        [Parameter()]
        [ValidateSet("CheckOnly", "CheckAndRestore")]
        [string]$Mode = "CheckOnly",

        [Parameter()]
        [string[]]$DatabaseFilter = @(),

        [Parameter()]
        [string]$ReportDirectory = "E:\TOOLS\HADES\Reports",

        [Parameter()]
        [string]$LogoUrl = "file:///E:/TOOLS/HADES/images.png"
    )

    $timestamp = Get-Date -Format "yyyyMMdd_HHmm"
    $timestampHuman = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    if (-not (Test-Path $ReportDirectory)) {
        New-Item -Path $ReportDirectory -ItemType Directory -Force | Out-Null
    }
    $reportPath = Join-Path $ReportDirectory "RestoreReport_${timestamp}.html"

    function Test-DiskSpace {
        param (
            [string]$BakFilePath,
            [object[]]$CsvGroup,
            [string]$SqlInstance,
            [pscredential]$Credential
        )

        try {
            $fileList = Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $Credential `
                -Query "RESTORE FILELISTONLY FROM DISK=N'$BakFilePath'" -EnableException 2>$null
        } catch {
            return @{ Ok = $false; Message = "RESTORE FILELISTONLY failed: $($_.Exception.Message)"; Files = @(); Volumes = @() }
        }

        $freeSpace = @{ }
        (Get-PSDrive -PSProvider FileSystem) | ForEach-Object {
            $freeSpace["$($_.Name):"] = $_.Free
        }

        $problems = @()
        $filesOut  = @()
        $volumes   = @{}

        foreach ($file in $fileList) {
            $destRow = $CsvGroup | Where-Object {
                ($_.name -replace '\s','').Trim().ToLower() -eq ($file.LogicalName -replace '\s','').Trim().ToLower()
            }
            if (-not $destRow) {
                $problems += "No mapping found in CSV for [$($file.LogicalName)]"
                continue
            }

            $destPath = $destRow.physical_name
            $volume   = try { Split-Path $destPath -Qualifier } catch { "UNKNOWN" }
            if (-not $volume) { $volume = "UNKNOWN" }

            $sizeBytes   = [int64]$file.Size
            $neededBytes = [math]::Round($sizeBytes * 1.15)
            $neededGB    = [math]::Round($neededBytes / 1GB, 2)
            $availGB     = if ($freeSpace.ContainsKey($volume)) { [math]::Round($freeSpace[$volume] / 1GB, 2) } else { 0 }
            $missingGB   = if ($availGB -lt $neededGB) { [math]::Round($neededGB - $availGB, 2) } else { 0 }

            if ($missingGB -gt 0) {
                $problems += "Volume $volume → Required: $neededGB GB | Available: $availGB GB"
            }

            if (-not $volumes.ContainsKey($volume)) {
                $volumes[$volume] = [PSCustomObject]@{
                    Volume      = $volume
                    NeededGB    = 0
                    AvailableGB = $availGB
                    MissingGB   = 0
                }
            }
            $volumes[$volume].NeededGB += $neededGB
            if ($volumes[$volume].AvailableGB -lt $volumes[$volume].NeededGB) {
                $volumes[$volume].MissingGB = [math]::Round($volumes[$volume].NeededGB - $volumes[$volume].AvailableGB, 2)
            }

            $filesOut += [PSCustomObject]@{
                LogicalName = $file.LogicalName
                FilePath    = $destPath
                SizeGB      = [math]::Round($sizeBytes / 1GB, 2)
            }
        }

        if ($problems.Count -eq 0) {
            return @{ Ok = $true; Message = "Disk space check passed."; Files = $filesOut; Volumes = $volumes.Values }
        } else {
            return @{ Ok = $false; Message = ($problems -join "`n"); Files = $filesOut; Volumes = $volumes.Values }
        }
    }

    Import-Module dbatools -ErrorAction Stop
    Set-DbatoolsInsecureConnection -SessionOnly

    $report      = @()
    $diskSummary = @{}

    $csvData = Import-Csv $CsvPath
    if ($DatabaseFilter.Count -gt 0) {
        $csvData = $csvData | Where-Object { $DatabaseFilter -contains $_.databasename }
    }
    $groups = $csvData | Group-Object databasename

    foreach ($grp in $groups) {
        $dbName      = $grp.Name
        $start       = Get-Date
        $status      = "Unknown"
        $details     = ""
        $bakFilePath = "N/A"
        $files       = @()

        try {
            $folder = Join-Path $BackupRoot $dbName
            if (-not (Test-Path $folder)) { throw "Backup folder not found: $folder" }
            $bakFile = Get-ChildItem $folder -Filter *.bak | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $bakFile) { throw "No .bak file found in $folder" }

            $bakFilePath = $bakFile.FullName

            $check = Test-DiskSpace -BakFilePath $bakFilePath -CsvGroup $grp.Group -SqlInstance $Instances[0] -Credential $SqlCredential
            $files = $check.Files
            foreach ($v in $check.Volumes) {
                if (-not $diskSummary.ContainsKey($v.Volume)) {
                    $diskSummary[$v.Volume] = $v
                } else {
                    $diskSummary[$v.Volume].NeededGB  += $v.NeededGB
                    $diskSummary[$v.Volume].MissingGB += $v.MissingGB
                }
            }

            if (-not $check.Ok) {
                Write-Host "   ✖ Not enough disk space." -ForegroundColor Red
                $status  = "Error"
                $details = "Disk space check failed:`n$($check.Message)"
            }
            elseif ($Mode -eq "CheckOnly") {
                Write-Host "   ✔ Disk space OK (CheckOnly mode)." -ForegroundColor Yellow
                $status  = "Success"
                $details = "Disk space validated. Restore skipped (CheckOnly mode)."
            }
            else {
                $fileMap = @{ }
                foreach ($row in $grp.Group) {
                    $fileMap[$row.name] = $row.physical_name
                }

                foreach ($inst in $Instances) {
                    Write-Host " → Restoring on $inst..." -ForegroundColor Gray
                    $prevWarn = $WarningPreference
                    $WarningPreference = 'Stop'
                    try {
                        Restore-DbaDatabase -SqlInstance $inst -SqlCredential $SqlCredential `
                            -Path $bakFilePath -DatabaseName $dbName -FileMapping $fileMap `
                            -WithReplace -NoRecovery -ErrorAction Stop | Out-Null
                        Write-Host "   ✔ Restore completed successfully." -ForegroundColor Green
                        $details += "[Instance: $inst] Restore completed successfully.`n"
                    } catch {
                        Write-Host "   ✖ Error on $inst : $($_.Exception.Message)" -ForegroundColor Red
                        $details += "[Instance: $inst] $($_.Exception.Message)`n"
                    } finally {
                        $WarningPreference = $prevWarn
                    }
                }
                $status = if ($details -match "Error") { "Error" } else { "Success" }
            }
        } catch {
            Write-Host "⛔ Setup error: $($_.Exception.Message)" -ForegroundColor Red
            $status = "Error"
            $details = "Setup error: $($_.Exception.Message)"
        }

        $duration = (Get-Date) - $start
        $report += [PSCustomObject]@{
            Database   = $dbName
            Status     = $status
            BackupFile = $bakFilePath
            Duration   = $duration.ToString("hh\:mm\:ss")
            Details    = $details.TrimEnd("`n")
            Files      = $files
        }
    }

    # Placeholder for report output
    $report | Out-GridView -Title "Restore Report Summary"
    $report | Export-Clixml -Path ($reportPath -replace '\.html$', '.xml')  # Exporta dados brutos
    Write-Host "`n📄 Restore report saved to: $reportPath" -ForegroundColor Cyan
}
