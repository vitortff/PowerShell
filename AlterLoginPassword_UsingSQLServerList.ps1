Set-DbatoolsInsecureConnection
$configFilePath = "E:\DBA\SQLLogins.csv"

Import-Csv -Path $configFilePath | ForEach-Object {

    $SourceInstanceName = ( $_.SourceSqlInstance -split '\\')[1]
    $LoginName = ($_.LoginName)
    $NewPassword = ($_.NewPassword)
    $sqlQuery = "ALTER LOGIN strata WITH PASSWORD = '$NewPassword';"
    

    #$sqlQuery
    Invoke-SqlCmd -ServerInstance $_.SourceSqlInstance -Query $sqlQuery
}
