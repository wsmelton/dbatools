function Get-DbaServerPermission {
    <#
    .SYNOPSIS
        Gets the server-level permissions for an instance

    .DESCRIPTION
        Gets the server-level permissions by enumerating through the instance-level objects

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Login
        The login(s) that exists as a Grantee to be returned

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Permission, Server, Security
        Author: Shawn Melton (@wsmelton)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaServerPermission

    .EXAMPLE
        PS C:\> Get-DbaServerPermission -SqlInstance server12

        Returns all the server-level permissions for server12

    .EXAMPLE
        PS C:\> Get-DbaServerPermission -SqlInstance server12 -Login dbatools\rick

        Returns all the server-level permissions assigned to dbatools\rick on server12
    #>
    [OutputType("Microsoft.SqlServer.Management.Smo.ServerPermissionInfo")]
    [CmdletBinding()]
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias('Grantee')]
        [string[]]$Login,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                foreach ($perm in $server.EnumServerPermissions()) {
                    if ( (Test-Bound Login) -and ($Login -notin $perm.Grantee)) { continue }
                    Add-Member -Force -InputObject $perm -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $perm -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $perm -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Select-DefaultView -InputObject $perm -ExcludeProperty ColumnName,ObjectSchema,ObjectID
                }
            } catch {
                Stop-Function -Message "Issue enumerating permissions on $instance" -Target $instance -ErrorRecord $_ -Continue
            }
        }
    }
}