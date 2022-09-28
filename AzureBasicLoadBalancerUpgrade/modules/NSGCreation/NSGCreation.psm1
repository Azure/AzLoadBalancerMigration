# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\UpdateVmssInstances\UpdateVmssInstances.psd1")
function NSGCreation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[NSGCreation] Initiating NSG Creation"

    log -Message "[NSGCreation] Looping all VMSS in the backend pool of the Load Balancer"
    $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object { $_.split("virtualMachines")[0] } | Select-Object -Unique
    foreach ($vmssId in $vmssIds) {
        $vmssName = $vmssId.split("/")[8]
        $vmssRg = $vmssId.Split('/')[4]
        $vmss = Get-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName

        # Check if VMSS already has a NSG
        log -Message "[NSGCreation] Checking if VMSS Named: $($vmss.Name) has a NSG"
        if (![string]::IsNullOrEmpty($vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations.NetworkSecurityGroup)) {
            log -Message "[NSGCreation] NSG detected in VMSS Named: $($vmss.Name) NetworkInterfaceConfigurations.NetworkSecurityGroup Id: $($vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations.NetworkSecurityGroup.Id)" -severity "Warning"
            log -Message "[NSGCreation] NSG will not be created for VMSS Named: $($vmss.Name)" -severity "Warning"
            break
        }
        log -Message "[NSGCreation] NSG not detected."

        log -Message "[NSGCreation] Creating NSG for VMSS: $vmssName"

        try {
            $ErrorActionPreference = 'Stop'
            $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $vmssRg -Name ("NSG-" + $vmss.Name) -Location $vmss.Location -Force
        }
        catch {
            $message = @"
            [NSGCreation] An error occured while creating NSG '$("NSG-"+$vmss.Name)'. TRAFFIC FROM LOAD BALANCER TO BACKEND POOL MEMBERS WILL
            BE BLOCKED UNTIL AN NSG WITH AN ALLOW RULE IS CREATED! To recover, manually create an NSG which allows traffic to the
            backend ports on the VM/VMSS and associate it with the VM, VMSS, or subnet. Error: $_
"@
            log 'Error' $message
            Exit
        }

        log -Message "[NSGCreation] NSG Named: $("NSG-"+$vmss.Name) created."

        # Adding NSG Rule for each Load Balancing Rule
        # Note: For now I'm assuming there is no way to have more than one VMSS in a single LB
        log -Message "[NSGCreation] Adding one NSG Rule for each Load Balancing Rule"
        $loadBalancingRules = $BasicLoadBalancer.LoadBalancingRules
        $priorityCount = 100
        foreach ($loadBalancingRule in $loadBalancingRules) {
            $networkSecurityRuleConfig = @{
                Name                                = ($loadBalancingRule.Name + "-loadBalancingRule")
                Protocol                            = $loadBalancingRule.Protocol
                SourcePortRange                     = "*"
                DestinationPortRange                = $loadBalancingRule.BackendPort
                SourceAddressPrefix                 = "*"
                DestinationAddressPrefix            = "*"
                SourceApplicationSecurityGroup      = $null
                DestinationApplicationSecurityGroup = $null
                Access                              = "Allow"
                Priority                            = $priorityCount
                Direction                           = "Inbound"
            }
            log -Message "[NSGCreation] Adding NSG Rule Named: $($networkSecurityRuleConfig.Name) to NSG Named: $($nsg.Name)"
            $nsg | Add-AzNetworkSecurityRuleConfig @networkSecurityRuleConfig > $null
            $priorityCount++
        }

        # Adding NSG Rule for each inboundNAT Rule
        log -Message "[NSGCreation] Adding one NSG Rule for each inboundNatRule"
        $networkSecurityRuleConfig = $null
        $inboundNatRules = $BasicLoadBalancer.InboundNatRules
        foreach ($inboundNatRule in $inboundNatRules) {
            $networkSecurityRuleConfig = @{
                Name                                = ($inboundNatRule.Name + "-NatRule")
                Protocol                            = $inboundNatRule.Protocol
                SourcePortRange                     = "*"
                DestinationPortRange                = [string]::IsNullOrEmpty($inboundNatRule.FrontendPortRangeStart) ? ($inboundNatRule.BackendPort).ToString() : (($inboundNatRule.FrontendPortRangeStart).ToString() + "-" + ($inboundNatRule.FrontendPortRangeEnd).ToString())
                SourceAddressPrefix                 = "*"
                DestinationAddressPrefix            = "*"
                SourceApplicationSecurityGroup      = $null
                DestinationApplicationSecurityGroup = $null
                Access                              = "Allow"
                Priority                            = $priorityCount
                Direction                           = "Inbound"
            }
            log -Message "[NSGCreation] Adding NSG Rule Named: $($networkSecurityRuleConfig.Name) to NSG Named: $($nsg.Name)"
            $nsg | Add-AzNetworkSecurityRuleConfig @networkSecurityRuleConfig > $null
            $priorityCount++
        }

        # Saving NSG
        log -Message "[NSGCreation] Saving NSG Named: $($nsg.Name)"
        try {
            $ErrorActionPreference = 'Stop'
            Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg > $null
        }
        catch {
            $message = @"
            [NSGCreation] An error occured while adding security rules to NSG '$("NSG-"+$vmss.Name)'. TRAFFIC FROM LOAD BALANCER TO BACKEND POOL MEMBERS WILL
            BE BLOCKED UNTIL AN NSG WITH AN ALLOW RULE IS CREATED! To recover, manually rules in NSG '$("NSG-"+$vmss.Name)' which allows traffic
            to the backend ports on the VM/VMSS and associate the NSG with the VM, VMSS, or subnet. Error: $_
"@
            log 'Error' $message
            Exit
        }

        # Adding NSG to VMSS
        log -Message "[NSGCreation] Adding NSG Named: $($nsg.Name) to VMSS Named: $($vmss.Name)"
        foreach ($networkInterfaceConfiguration in $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
            $networkInterfaceConfiguration.NetworkSecurityGroup = $nsg.Id
        }

        # Saving VMSS
        log -Message "[NSGCreation] Saving VMSS Named: $($vmss.Name)"
        try {
            $ErrorActionPreference = 'Stop'
            Update-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName -VirtualMachineScaleSet $vmss > $null
        }
        catch {
            $message = @"
            [NSGCreation] An error occured while updating VMSS '$($vmss.name)' to associate the new NSG '$("NSG-"+$vmss.Name)'. TRAFFIC FROM LOAD BALANCER TO
            BACKEND POOL MEMBERS WILL BE BLOCKED UNTIL AN NSG WITH AN ALLOW RULE IS CREATED! To recover, manually associate NSG '$("NSG-"+$vmss.Name)'
            with the VM, VMSS, or subnet. Error: $_
"@
            log 'Error' $message
            Exit
        }

        UpdateVmssInstances -vmss $vmss
    }
    log -Message "[NSGCreation] NSG Creation Completed"
}

Export-ModuleMember -Function NSGCreation