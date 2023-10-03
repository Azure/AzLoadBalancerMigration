# Import Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")

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
            $message = "[AddLoadBalancerBackendAddressPool] An error occured when adding a backend pool to the new Standard LB '$($StdLoadBalancer.Name)'. To recover, address the cause of the following error, then follow the steps at https://aka.ms/basiclbupgradefailure to retry the migration."
            log 'Error' $message -terminateOnError
        }
    }

    try {
        log -Message "[AddLoadBalancerBackendAddressPool] Saving added BackendAddressPool to Standard Load Balancer $($StdLoadBalancer.Name)"
        $StdLoadBalancer | Set-AzLoadBalancer > $null
    }
    catch {
        $message = "[AddLoadBalancerBackendAddressPool] An error occured when saving the added backend pools to the new Standard LB '$($StdLoadBalancer.Name)'. To recover, address the cause of the following error, then follow the steps at https://aka.ms/basiclbupgradefailure to retry the migration."
        log 'Error' $message -terminateOnError
    }
}
