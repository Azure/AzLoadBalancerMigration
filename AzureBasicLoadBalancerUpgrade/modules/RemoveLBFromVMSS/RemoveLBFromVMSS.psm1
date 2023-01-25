
# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\UpdateVmssInstances\UpdateVmssInstances.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\GetVmssFromBasicLoadBalancer\GetVmssFromBasicLoadBalancer.psd1")
function RemoveLBFromVmss {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer
    )
    log -Message "[RemoveLBFromVmss] Initiating removal of LB $($BasicLoadBalancer.Name) from VMSS $($VMSS.Name)"
    log -Message "[RemoveLBFromVmss] Looping all VMSS from Basic Load Balancer $($BasicLoadBalancer.Name)"

    log -Message "[RemoveLBFromVmss] Building VMSS object from Basic Load Balancer $($BasicLoadBalancer.Name)"
    $vmss = GetVmssFromBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer

    log -Message "[RemoveLBFromVmss] Cleaning healthProbe from NetworkProfile of VMSS $($vmss.Name)"
    $vmss.VirtualMachineProfile.NetworkProfile.healthProbe = $null

    log -Message "[RemoveLBFromVmss] Checking Upgrade Policy Mode of VMSS $($vmss.Name)"
    if ($vmss.UpgradePolicy.Mode -eq "Rolling") {
        log -Message "[RemoveLBFromVmss] Upgrade Policy Mode of VMSS $($vmss.Name) is Rolling"
        log -Message "[RemoveLBFromVmss] Setting Upgrade Policy Mode of VMSS $($vmss.Name) to Manual"
        $vmss.UpgradePolicy.Mode = "Manual"
    }

    log -Message "[RemoveLBFromVmss] Cleaning LoadBalancerBackendAddressPools from Basic Load Balancer $($BasicLoadBalancer.Name)"
    foreach ($networkInterfaceConfiguration in $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
        foreach ($ipConfiguration in $networkInterfaceConfiguration.IpConfigurations) {
            $ipConfiguration.loadBalancerBackendAddressPools = $null
            $ipConfiguration.loadBalancerInboundNatPools = $null
        }
    }
    log -Message "[RemoveLBFromVmss] Updating VMSS $($vmss.Name)"

    try {
        Update-AzVmss -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name -VirtualMachineScaleSet $vmss -ErrorAction Stop > $null
    }
    catch {
        $message = @"
            [RemoveLBFromVmss] An error occured while updating VMSS '$($vmss.Name)' in resource group '$($vmss.ResourceGroupName)' to remove it from a backend pool on load balancer
            '$($BasicLoadBalancer.Name)'. The script will be unable to delete the basic load balancer unless all backend pools are empty and
            must exit. To recover address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup
            State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
        log 'Error' $message -terminateOnError
    }

    # Update the VMSS instances
    UpdateVmssInstances -vmss $vmss

    log -Message "[RemoveLBFromVmss] Removing Basic Loadbalancer $($BasicLoadBalancer.Name) from Resource Group $($BasicLoadBalancer.ResourceGroupName)"

    try {
        Remove-AzLoadBalancer -ResourceGroupName $BasicLoadBalancer.ResourceGroupName -Name $BasicLoadBalancer.Name -Force -ErrorAction Stop > $null
    }
    Catch {
        $message = @"
            [RemoveLBFromVmss] A failure occured when attempting to delete the basic load balancer '$($BasicLoadBalancer.Name)'. The script cannot continue as the front
            end addresses will not be available to reassign to the new Standard load balancer. To recover
            address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup
            State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
        log 'Error' $message -terminateOnError
    }
    log -Message "[RemoveLBFromVmss] Removal of Basic Loadbalancer $($BasicLoadBalancer.Name) Completed"
}

Export-ModuleMember -Function RemoveLBFromVmss