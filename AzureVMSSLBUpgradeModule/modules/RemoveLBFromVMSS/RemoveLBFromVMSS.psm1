
# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\UpdateVmssInstances\UpdateVmssInstances.psd1")
function RemoveLBFromVMSS {
    param (
        [Parameter(Mandatory = $True)][string[]] $vmssIds,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer
    )
    log -Message "[RemoveLBFromVMSS] Initiating removal of LB $($BasicLoadBalancer.Name) from VMSS $($VMSS.Name)"
    log -Message "[RemoveLBFromVMSS] Looping all VMSS from Basic Load Balancer $($BasicLoadBalancer.Name)"
    foreach ($vmssId in $vmssIds) {
        $vmssRg = $vmssId.Split('/')[4]
        $vmssName = $vmssId.Split('/')[8]
        log -Message "[RemoveLBFromVMSS] Loading VMSS $vmssName from RG $vmssRg"

        try {
            $ErrorActionPreference = 'Stop'
            $vmss = Get-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName
        }
        catch {
            $message = "[RemoveLBFromVMSS] An error occured when getting VMSS '$($vmssName)' in resource group '$($vmssRG)'. The VMSS may have been removed already, script will continue. Error: $_"
            log 'Warning' $message
            continue
        }

        If ($vmss.UpgradePolicy.Mode -ne 'Manual') {
            log 'Error' -Message "[RemoveLBFromVMSS] VMSS '$($vmss.Name)' is configured with Upgrade Policy '$($vmss.UpgradePolicy.Mode)', which is not yet supported by the script; exiting..."
            
            #temp
            throw "VMSSs with upgrade policy other than 'Manual' are not handled by the script yet!"
        }

        # ###### Attention ######
        # *** We may have to check other scenarios like with ApplicationGatewayBackendAddressPools, ApplicationSecurityGroups and LoadBalancerInboundNatPools
        # #######################
        log -Message "[RemoveLBFromVMSS] Cleanning LoadBalancerBackendAddressPools from Basic Load Balancer $($BasicLoadBalancer.Name)"
        foreach ($networkInterfaceConfiguration in $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
            foreach ($ipConfiguration in $networkInterfaceConfiguration.IpConfigurations) {
                $ipConfiguration.loadBalancerBackendAddressPools = $null
                #$ipConfiguration.LoadBalancerInboundNatPools = $null
            }
        }
        log -Message "[RemoveLBFromVMSS] Updating VMSS $vmssName"

        try {
            Update-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName -VirtualMachineScaleSet $vmss -ErrorAction Stop > $null
        }
        catch {
            $message = @"
                [RemoveLBFromVMSS] An error occured while updating VMSS '$vmssName' in resource group '$vmssRG' to remove it from a backend pool on load balancer 
                '$($BasicLoadBalancer.Name)'. The script will be unable to delete the basic load balancer unless all backend pools are empty and 
                must exit. To recover, add any backend pool members back to the backend pools (see the backup 
                '$('State-' + $BasicLoadBalancerName + '-' + $BasicLoadBalancer.ResourceGroupName + '...')' state file for original pool membership), 
                address the error, and try again. Error: $_
"@
            log 'Error' $message
            Exit
        }

        If ($vmss.UpgradePolicy.Mode -eq 'Manual') {
            log -Message "[RemoveLBFromVMSS] VMSS '$vmss.Name' is configured with Upgrade Policy '$($vmss.UpgradePolicy)', so each VMSS instance will have the updated VMSS network profile applied by the script."
            UpdateVmssInstances -vmss $vmss
        }
        Else {
            # ###### TO-DO ######
            # *** Either use a Sleep or other method of ensuring the change has been applied to all instance before attempting to add the VMSS to the Standard LB! 
            # #######################

            log -Message "[RemoveLBFromVMSS] VMSS '$vmss.Name' is configured with Upgrade Policy '$($vmss.UpgradePolicy.Mode)', so the update NetworkProfile will be applied automatically."
        }
    }

    log -Message "[RemoveLBFromVMSS] Removing Basic Loadbalancer $($BasicLoadBalancer.Name) from Resource Group $($BasicLoadBalancer.ResourceGroupName)"

    try {
        Remove-AzLoadBalancer -ResourceGroupName $BasicLoadBalancer.ResourceGroupName -Name $BasicLoadBalancer.Name -Force -ErrorAction Stop > $null
    }
    Catch {
        $message = @"
            [RemoveLBFromVMSS] A failure occured when attempting to delete the basic load balancer '$($BasicLoadBalancer.Name)'. The script cannot continue as the front 
            end addresses will not be available to reassign to the new Standard load balancer. To recovery, add any backend pool members back to the 
            backend pools (see the backup '$('State-' + $BasicLoadBalancerName + '-' + $BasicLoadBalancer.ResourceGroupName + '...')' state file for 
            original pool membership), address the following error, and try again. Error: $_
"@
        log 'Error' $message
        Exit
    }
    log -Message "[RemoveLBFromVMSS] Removal of Basic Loadbalancer $($BasicLoadBalancer.Name) Completed"
}

Export-ModuleMember -Function RemoveLBFromVMSS