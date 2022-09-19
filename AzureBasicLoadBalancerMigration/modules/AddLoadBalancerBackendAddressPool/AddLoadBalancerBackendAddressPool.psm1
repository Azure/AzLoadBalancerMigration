# Import Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")

function AddLoadBalancerBackendAddressPool {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )

    foreach ($basicBackendAddressPool in $BasicLoadBalancer.BackendAddressPools) {
        log -Message "[AddLoadBalancerBackendAddressPool] Adding BackendAddressPool $($basicBackendAddressPool.Name)"
        try {
            $ErrorActionPreference = 'Stop'
            $StdLoadBalancer | Add-AzLoadBalancerBackendAddressPoolConfig -Name $basicBackendAddressPool.Name > $null
        }
        catch {
            $message = @"
                [AddLoadBalancerBackendAddressPool] An error occured when adding a backend pool to the new Standard LB '$($StdLoadBalancer.Name)'. To recover
                address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup
                State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
            log 'Error' $message
            Exit
        }
    }

    try {
        log -Message "[AddLoadBalancerBackendAddressPool] Saving added BackendAddressPool to Standard Load Balancer $($StdLoadBalancer.Name)"
        $StdLoadBalancer | Set-AzLoadBalancer > $null
    }
    catch {
        $message = @"
        [AddLoadBalancerBackendAddressPool] An error occured when saving the added backend pools to the new Standard LB '$($StdLoadBalancer.Name)'. To recover
        address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup
        State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
        log 'Error' $message
        Exit
    }
}