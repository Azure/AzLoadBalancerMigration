
# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
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
        $vmss = Get-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName
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
        Update-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName -VirtualMachineScaleSet $vmss
        log -Message "[RemoveLBFromVMSS] Updating VMSS Instances"
        $vmssIntances = Get-AzVmssVM -ResourceGroupName $vmssRg -VMScaleSetName $vmssName
        foreach ($vmssInstance in $vmssIntances) {
            log -Message "[RemoveLBFromVMSS] Updating VMSS Instance $($vmssInstance.Name)"
            Update-AzVmssInstance -ResourceGroupName $vmssRg -VMScaleSetName $vmssName -InstanceId $vmssInstance.InstanceId
        }
    }
    log -Message "[RemoveLBFromVMSS] Removing Basic Loadbalancer $($BasicLoadBalancer.Name) from Resource Group $($BasicLoadBalancer.ResourceGroupName)"
    Remove-AzLoadBalancer -ResourceGroupName $BasicLoadBalancer.ResourceGroupName -Name $BasicLoadBalancer.Name -Force
    log -Message "[PublicFEMigration] Removal of Basic Loadbalancer $($BasicLoadBalancer.Name) Completed"
}

Export-ModuleMember -Function RemoveLBFromVMSS