Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\UpdateVmss\UpdateVmss.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\UpdateVmssInstances\UpdateVmssInstances.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\GetVMSSFromBasicLoadBalancer\GetVMSSFromBasicLoadBalancer.psd1")
Function RemoveVMSSPublicIPConfig {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer
    )

    log -Message "[RemoveVMSSPublicIPConfig] Removing Public IP Address configuration from VMSS $($vmss.Name)"

    $vmss = GetVMSSFromBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer

    $pipConfigRemoved = $false
    ForEach ($nic in $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
        ForEach ($ipConfig in $nic.IpConfigurations) {

            If ($null -ne $ipConfig.PublicIpAddressConfiguration) {
                log -Message "[RemoveVMSSPublicIPConfig] Removing public IP address configuration '$($ipConfig.PublicIpAddressConfiguration.Name)' from IPConfig '$($ipConfig.Name)' on NIC '$($nic.Name)'"
                $ipConfig.PublicIpAddressConfiguration = $null
                $pipConfigRemoved = $true
            }
        }
    }

    If ($pipConfigRemoved) {
        log -Message "[RemoveVMSSPublicIPConfig] Updating vmss '$($vmss.Name)' to apply removal of public IP address configuration"
        log -Severity Warning -Message "[RemoveVMSSPublicIPConfig] Removing the Public IP Configs from the VMSS will result in new Public IPs being assigned post migration."

        UpdateVmss -vmss $vmss

        UpdateVmssInstances -vmss $vmss
    }

    log -Message "[RemoveVMSSPublicIPConfig] Completed removing Public IP Address configuration from VMSS $($vmss.Name). PIPs removed: '$pipConfigRemoved'"
}

Function AddVMSSPublicIPConfig {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $refVmss
    )

    log -Message "[AddVMSSPublicIPConfig] Adding Public IP Address configuration back to VMSS $($vmss.Name) IP Configs"

    $vmss = GetVMSSFromBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer

    $pipConfigAdded = $false
    ForEach ($nic in $refVmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
        Foreach ($ipConfig in $nic.IpConfigurations) {
            If ($null -ne $ipConfig.PublicIpAddressConfiguration) {
                log -Message "[AddVMSSPublicIPConfig] Adding public IP address configuration '$($ipConfig.PublicIpAddressConfiguration.Name)' on IPConfig '$($ipConfig.Name)' on NIC '$($nic.Name)' pf VMSS '$($vmss.Name)'"
                
                $vmssNic = $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations | Where-Object {$_.Name -eq $nic.Name}
                $vmssIpConfig = $vmssNic.IpConfigurations | Where-Object {$_.Name -eq $ipConfig.Name}

                log -Message "[AddVMSSPublicIPConfig] Changing Public IP Address configuration SKU to Standard"
                $ipConfig.PublicIpAddressConfiguration.Sku.Name = "Standard"

                $vmssIpConfig.PublicIpAddressConfiguration = $ipConfig.PublicIpAddressConfiguration

                $pipConfigAdded = $true
            }
        }
    }

    If ($pipConfigAdded) {
        log -Message "[AddVMSSPublicIPConfig] Updating vmss '$($vmss.Name)' to apply addition of public IP address configuration"

        UpdateVmss -vmss $vmss

        UpdateVmssInstances -vmss $vmss
    }
}

Export-ModuleMember -Function RemoveVMSSPublicIPConfig, AddVMSSPublicIPConfig
