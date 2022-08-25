# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\UpdateVmssInstances\UpdateVmssInstances.psd1")
function BackendPoolMigration {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[BackendPoolMigration] Initiating Backend Pool Migration"
    log -Message "[BackendPoolMigration] Looping all BackendAddressPools"
    foreach ($BackendAddressPool in $BasicLoadBalancer.BackendAddressPools) {
        log -Message "[BackendPoolMigration] Adding BackendAddressPool $($BackendAddressPool.Name)"
        $StdLoadBalancer | Add-AzLoadBalancerBackendAddressPoolConfig -Name $BackendAddressPool.Name | Set-AzLoadBalancer
        log -Message "[BackendPoolMigration] Adding Standard Load Balancer back to the VMSS"
        $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object{$_.split("virtualMachines")[0]} | Select-Object -Unique
        $BackendIpConfigurationName = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object{$_.split("/")[-1]} | Select-Object -Unique
        foreach ($vmssId in $vmssIds) {
            $vmssName = $vmssId.split("/")[8]
            $vmssRg = $vmssId.Split('/')[4]
            $vmss = Get-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName
            log -Message "[BackendPoolMigration] Adding BackendAddressPool to VMSS $($vmss.Name)"
            foreach ($networkInterfaceConfiguration in $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
                foreach ($ipConfiguration in $networkInterfaceConfiguration.IpConfigurations) {
                    if ($ipConfiguration.Name -eq $BackendIpConfigurationName) {
                        # Fail with error:
                        #SetValueInvocationException: Exception setting "loadBalancerBackendAddressPools":
                        #"Cannot convert the "Microsoft.Azure.Commands.Network.Models.PSBackendAddressPool"
                        # value of type "Microsoft.Azure.Commands.Network.Models.PSBackendAddressPool" to type
                        #"System.Collections.Generic.IList`1[Microsoft.Azure.Management.Compute.Models.SubResource]"."

                        # Found a reference Here that might fix the issue: https://github.com/jagilber/powershellScripts/blob/master/azure-az-vmss-add-appgw.ps1
                        $ipConfiguration.loadBalancerBackendAddressPools = ($StdLoadBalancer.BackendAddressPools | Where-Object{$_.Name -eq $BackendAddressPool.Name})
                    }
                }
            }
            log -Message "[BackendPoolMigration] Saving VMSS $($vmss.Name)"
            Update-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName -VirtualMachineScaleSet $vmss
            log -Message "[BackendPoolMigration] Updating VMSS Instances $($vmss.Name)"
            UpdateVmssInstances -vmss $vmss
        }
    }
    log -Message "[BackendPoolMigration] Backend Pool Migration Completed"
}

Export-ModuleMember -Function BackendPoolMigration