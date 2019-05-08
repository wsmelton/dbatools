function Compare-DbaDbData {
    <#
    .SYNOPSIS


    .DESCRIPTION


    .PARAMETER SourceSqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER DestinationSqlInstance
        The target SQL Server instance or instances.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER SourceDatabase
        Databases to process

    .PARAMETER DestinationDatabase
        Databases to process

    .PARAMETER Table
        Tables to process. By default all the tables will be processed

    .PARAMETER ExcludeEqual
        Exclude rows that are equal

    .PARAMETER ExludeDifferent
        Exclude rows that are different

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Compare Data
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Compare-DbaDbData

    .EXAMPLE


    #>
    [CmdLetBinding()]
    param (
        [DbaInstanceParameter]$SourceSqlInstance,
        [PSCredential]$SourceSqlCredential,
        [DbaInstanceParameter]$DestinationSqlInstance,
        [PSCredential]$DestinationSqlCredential,
        [string]$SourceDatabase,
        [string]$DestinationDatabase,
        [string[]]$Table,
        [switch]$ExcludeEqual,
        [switch]$ExludeDifferent,
        [switch]$EnableException
    )

    begin {
        # Checking parameters
        if (-not $SourceSqlInstance) {
            Stop-Function -Message "Please enter a source instance"
            return
        }

        if (-not $SourceDatabase) {
            Stop-Function -Message "Please enter a source database"
            return
        }

        if (-not $DestinationSqlInstance) {
            Write-Message -Level Verbose -Message "No destination instance given. Assuming the same as -SourceSqlInstance"
            $DestinationSqlInstance = $SourceSqlInstance
        }

        if (-not $DestinationDatabase) {
            if ($SourceSqlInstance -ne $DestinationSqlInstance) {
                Write-Message -Level Verbose -Message "No destination database given. Assuming the same as -SourceDatabase"
                $DestinationDatabase = $SourceDatabase
            } else {
                Stop-Function -Message "Please enter a destination database that's different from -SourceDatabase"
                return
            }
        }

        if ($ExcludeEqual -and $ExludeDifferent) {
            Stop-Function -Message "Invalid combination of parameters. You cannot use -ExcludeEqual and -ExcludeDifferent together"
            return
        }

        # Connect to the source and destination instances
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $SourceSqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $SourceSqlInstance
        }

        try {
            $destServer = Connect-SqlInstance -SqlInstance $DestinationSqlInstance -SqlCredential $DestinationSqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $DestinationSqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $DestinationSqlInstance
        }

        # Check the instances
        if ($sourceServer.Databases.Name -notcontains $SourceDatabase) {
            Stop-Function -Message "Could not find database $SourceDatabase on $SourceSqlInstance" -ErrorRecord $_ -Target $SourceDatabase
        }

        if ($destServer.Databases.Name -notcontains $DestinationDatabase) {
            Stop-Function -Message "Could not find database $DestinationDatabase on $DestinationSqlInstance" -ErrorRecord $_ -Target $DestinationDatabase
        }

    }

    process {
        if (Test-FunctionInterrupt) { return }

        $tableCollection = @()

        if ($Table) {
            foreach ($t in $Table) {
                if ($t.Contains(".")) {
                    $tableNameParts = $t.Split(".")
                    $tableCollection = $sourceServer.Databases[$SourceDatabase].Tables | Where-Object { $_.Schema -eq $tableNameParts[0] -and $_.Name -eq $tableNameParts[1] }
                }
            }

        } else {
            $tableCollection = $sourceServer.Databases[$SourceDatabase].Tables
        }

        if ($tableCollection.Count -ge 1) {

            foreach ($tableobject in $tableCollection) {

                $query = "SELECT * FROM [$($tableobject.Schema)].[$($tableobject.name)]"

                $sourceData = Invoke-DbaQuery -SqlInstance $sourceServer -SqlCredential $SourceSqlCredential -Database $SourceDatabase -Query $query
                $destData = Invoke-DbaQuery -SqlInstance $destServer -SqlCredential $DestinationSqlCredential -Database $DestinationDatabase -Query $query

                $result = Compare-Object -ReferenceObject $sourceData -DifferenceObject $destData -Property ($sourceData | Get-Member | Where-Object MemberType -eq Property | Select-Object Name -ExpandProperty Name)

                if ($ExcludeEqual) {
                    $result = $result | Where-Object SideIndicator -ne "=="
                }

                if ($ExludeDifferent) {
                    $result = $result | Where-Object SideIndicator -notin "<=", "=>"
                }

                $results
            }

        }


    }

}