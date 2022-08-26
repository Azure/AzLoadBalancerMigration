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
    foreach ($basicBackendAddressPool in $BasicLoadBalancer.BackendAddressPools) {
        log -Message "[BackendPoolMigration] Adding BackendAddressPool $($basicBackendAddressPool.Name)"
        $StdLoadBalancer | Add-AzLoadBalancerBackendAddressPoolConfig -Name $basicBackendAddressPool.Name | Set-AzLoadBalancer
        log -Message "[BackendPoolMigration] Adding Standard Load Balancer back to the VMSS"
        $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object{$_.split("virtualMachines")[0]} | Select-Object -Unique
        $BackendIpConfigurationName = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object{$_.split("/")[-1]} | Select-Object -Unique
        foreach ($vmssId in $vmssIds) {
            $vmssName = $vmssId.split("/")[8]
            $vmssRg = $vmssId.Split('/')[4]
            $vmssStatic = Get-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName
            $vmss = Get-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName
            log -Message "[BackendPoolMigration] Adding BackendAddressPool to VMSS $($vmss.Name)"
            foreach ($networkInterfaceConfiguration in $vmssStatic.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
                foreach ($ipConfiguration in $networkInterfaceConfiguration.IpConfigurations) {
                    if ($ipConfiguration.Name -contains $BackendIpConfigurationName) {
                        $vmssipConfigDef = @{
                            Name = $ipConfiguration.Name
                            # ***Need to check what to do about InboundNatPools
                            #LoadBalancerInboundNatPoolsId = $null
                            LoadBalancerBackendAddressPoolsId = ($StdLoadBalancer.BackendAddressPools | Where-Object{$_.Name -eq $basicBackendAddressPool.Name}).Id
                            SubnetId = $ipConfiguration.Subnet.Id
                        }
                        $vmssipConfig = New-azVmssIPConfig @vmssipConfigDef
                        $nicconfigname = $networkInterfaceConfiguration.Name
                        Remove-azVmssNetworkInterfaceConfiguration -VirtualMachineScaleSet $vmss -Name $nicconfigname
                        Add-azVmssNetworkInterfaceConfiguration -VirtualMachineScaleSet $vmss -Name $nicconfigname -Primary $true -IPConfiguration $vmssipConfig
                    }
                }
            }
            log -Message "[BackendPoolMigration] Saving VMSS $($vmss.Name)"
            Update-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName -VirtualMachineScaleSet $vmss
            log -Message "[BackendPoolMigration] Updating VMSS Instances $($vmss.Name)"
            UpdateVmssInstances -vmss $vmss
        }
    }
    #log -Message "[BackendPoolMigration] StackTrace $($StackTrace)" -Severity "Debug"
    log -Message "[BackendPoolMigration] Backend Pool Migration Completed"
}

Export-ModuleMember -Function BackendPoolMigration