# =========================================================
# SQL Server Instance Comparison Script (Sectioned Report)
# =========================================================

# Ensure dbatools is installed
if (-not (Get-Module -ListAvailable -Name dbatools)) {
    Install-Module dbatools -Scope CurrentUser -Force
}
Import-Module dbatools -Force

# ================= CONFIG =================
$configFilePath = "E:\TOOLS\SCRIPTS\SQLServerInstances.csv"
$outputFolder   = "C:\Temp"

# ComparisonMode:
#   Upgrade = allows expected differences (version, CPU, memory, etc.)
#   Clone   = strict comparison (almost everything should match)
$ComparisonMode = "Upgrade"

# Instance properties that are EXPECTED to differ during upgrades
$ExpectedUpgradeDifferences = @(
    'Edition','VersionString','BuildNumber','ProductLevel',
    'Processors','PhysicalMemory','OSVersion','Platform',
    'EngineEdition','HostPlatform','HostDistribution',
    'HostRelease','ServiceTier','HardwareGeneration'
)

# Excluded system logins
$ExcludedLogins = @(
    'sa',
    '##MS_PolicyTsqlExecutionLogin##',
    '##MS_PolicyEventProcessingLogin##',
    'NT AUTHORITY\SYSTEM',
    'NT SERVICE\MSSQLSERVER',
    'NT SERVICE\SQLSERVERAGENT'
)

if (-not (Test-Path $outputFolder)) {
    New-Item -Path $outputFolder -ItemType Directory | Out-Null
}

function Safe-Name ($n) {
    return ($n -replace '[\\\/:*?"<>|]', '_')
}

# ---------- HTML helpers ----------
function Get-StatusColor($status) {
    switch ($status) {
        'MATCH'               { 'color:#228B22;font-weight:bold;' }
        'EXPECTED DIFFERENCE' { 'color:#FF8C00;font-weight:bold;' }
        default               { 'color:#CC0000;font-weight:bold;' }
    }
}

function New-SectionTable {
    param (
        [string] $Title,
        [array]  $Rows,
        [string[]] $Columns
    )

    if (-not $Rows -or $Rows.Count -eq 0) {
        return "<h3>$Title</h3><p><i>No items found.</i></p>"
    }

    $header = ($Columns | ForEach-Object { "<th>$_</th>" }) -join ''
    $body = foreach ($r in $Rows) {
        "<tr>" +
        ($Columns | ForEach-Object {
            if ($_ -eq 'Status') {
                "<td style='$(Get-StatusColor $r.Status)'>$($r.Status)</td>"
            } else {
                "<td>$($r.$_)</td>"
            }
        }) -join '' +
        "</tr>"
    }

@"
<h3>$Title</h3>
<table>
<tr>$header</tr>
$($body -join "`n")
</table>
"@
}

# ================= MAIN =================
Import-Csv -Path $configFilePath | ForEach-Object {

    $Source = $_.SourceSqlInstance
    $Dest   = $_.DestinationSqlInstance

    Write-Host "Comparing $Source vs $Dest (Mode: $ComparisonMode)"

    $instSrc = Get-DbaInstanceProperty -SqlInstance $Source
    $instDst = Get-DbaInstanceProperty -SqlInstance $Dest

    $dstLookup = @{}
    foreach ($p in $instDst) {
        if ($p.Name) { $dstLookup[$p.Name] = $p.Value }
    }

    # -------- Instance Properties ----------
    $InstanceRows = foreach ($p in $instSrc) {
        if (-not $p.Name) { continue }

        $srcVal = $p.Value
        $dstVal = $dstLookup[$p.Name]

        if ($srcVal -eq $dstVal) {
            $status = 'MATCH'
        }
        elseif ($ComparisonMode -eq 'Upgrade' -and $ExpectedUpgradeDifferences -contains $p.Name) {
            $status = 'EXPECTED DIFFERENCE'
        }
        else {
            $status = 'DIFFERENT'
        }

        [PSCustomObject]@{
            Property    = $p.Name
            Source      = $srcVal
            Destination = $dstVal
            Status      = $status
        }
    }

    # -------- sp_configure ----------
    $cfgSrc = Get-DbaSpConfigure -SqlInstance $Source -ErrorAction SilentlyContinue
    $cfgDst = Get-DbaSpConfigure -SqlInstance $Dest -ErrorAction SilentlyContinue

    $cfgDstLookup = @{}
    foreach ($c in $cfgDst) {
        if ($c.ConfigName) { $cfgDstLookup[$c.ConfigName] = $c.RunningValue }
    }

    $SpConfigRows = foreach ($c in $cfgSrc) {
        $dstVal = $cfgDstLookup[$c.ConfigName]

        [PSCustomObject]@{
            Property    = $c.ConfigName
            Source      = $c.RunningValue
            Destination = $dstVal
            Status      = if ($c.RunningValue -eq $dstVal) { 'MATCH' } else { 'DIFFERENT' }
        }
    }

    # -------- Generic object compare ----------
    function Compare-Objects {
        param ($SrcList, $DstList, $Prop)

        $srcNames = @()
        $dstNames = @()
        if ($SrcList) { $srcNames = $SrcList | ForEach-Object { $_.$Prop } | Where-Object { $_ } }
        if ($DstList) { $dstNames = $DstList | ForEach-Object { $_.$Prop } | Where-Object { $_ } }

        $all = ($srcNames + $dstNames) | Sort-Object -Unique

        foreach ($n in $all) {
            $inSrc = if ($srcNames -contains $n) { 'Yes' } else { 'No' }
            $inDst = if ($dstNames -contains $n) { 'Yes' } else { 'No' }

            $status = if (($inSrc -eq 'Yes') -and ($inDst -eq 'Yes')) {
                'MATCH'
            }
            elseif ($inSrc -eq 'Yes') {
                'Missing on Destination'
            }
            else {
                'Missing on Source'
            }

            [PSCustomObject]@{
                Object      = $n
                Source      = $inSrc
                Destination = $inDst
                Status      = $status
            }
        }
    }

    # -------- Object collections ----------
    $LoginsRows    = Compare-Objects (Get-DbaLogin $Source | Where-Object { $_.Name -notin $ExcludedLogins }) (Get-DbaLogin $Dest) 'Name'
    $JobsRows      = Compare-Objects (Get-DbaAgentJob $Source) (Get-DbaAgentJob $Dest) 'Name'
    $SchedulesRows = Compare-Objects (Get-DbaAgentSchedule $Source) (Get-DbaAgentSchedule $Dest) 'Name'
    $AlertsRows    = Compare-Objects (Get-DbaAgentAlert $Source) (Get-DbaAgentAlert $Dest) 'Name'
    $OperatorsRows = Compare-Objects (Get-DbaAgentOperator $Source) (Get-DbaAgentOperator $Dest) 'Name'
    $CredRows      = Compare-Objects (Get-DbaCredential $Source) (Get-DbaCredential $Dest) 'CredentialName'
    $ProxyRows     = Compare-Objects (Get-DbaAgentProxy $Source) (Get-DbaAgentProxy $Dest) 'Name'

    # -------- HTML ----------
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $outFile = Join-Path $outputFolder "Compare_$(Safe-Name $Source)_vs_$(Safe-Name $Dest)_$ts.html"

@"
<html>
<head>
<style>
body { font-family: Arial; font-size: 13px; }
table { border-collapse: collapse; width: 100%; margin-bottom: 25px; }
th, td { border: 1px solid #999; padding: 6px; }
th { background-color: #E6E6E6; }
h1,h2,h3 { margin-top: 25px; }
</style>
</head>
<body>

<h1>SQL Server Instance Comparison</h1>
<h2>$Source vs $Dest</h2>
<p><b>Comparison Mode:</b> $ComparisonMode</p>

$(New-SectionTable 'Instance Properties' $InstanceRows @('Property','Source','Destination','Status'))
$(New-SectionTable 'sp_configure Settings' $SpConfigRows @('Property','Source','Destination','Status'))
$(New-SectionTable 'Logins' $LoginsRows @('Object','Source','Destination','Status'))
$(New-SectionTable 'SQL Agent Jobs' $JobsRows @('Object','Source','Destination','Status'))
$(New-SectionTable 'SQL Agent Schedules' $SchedulesRows @('Object','Source','Destination','Status'))
$(New-SectionTable 'SQL Agent Alerts' $AlertsRows @('Object','Source','Destination','Status'))
$(New-SectionTable 'SQL Agent Operators' $OperatorsRows @('Object','Source','Destination','Status'))
$(New-SectionTable 'Credentials' $CredRows @('Object','Source','Destination','Status'))
$(New-SectionTable 'Agent Proxies' $ProxyRows @('Object','Source','Destination','Status'))

</body>
</html>
"@ | Out-File -FilePath $outFile -Encoding UTF8

    Write-Host "✅ Report generated: $outFile"
}
