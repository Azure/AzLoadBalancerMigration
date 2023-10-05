# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/UpdateVmssInstances/UpdateVmssInstances.psd1")

function _AddLBNSGSecurityRules {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $true, ParameterSetName = 'byNSGID')][string] $nsgId,
        [Parameter(Mandatory = $True, ParameterSetName = 'byNSGObject')][Microsoft.Azure.Commands.Network.Models.PSNetworkSecurityGroup] $nsg
    )

    log -Message "[_AddLBNSGSecurityRules] Adding NSG security rules to NSG '$($nsgId)$($nsg.Name)' to ensure Load Balancer traffic is allowed..."
    
    If (!$nsg) {
        $nsg = Get-AzResource -ResourceId $nsgId | Get-AzNetworkSecurityGroup
    }

    log -Message "[_AddLBNSGSecurityRules] Adding one NSG Rule for each Load Balancing Rule"
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
        log -Message "[_AddLBNSGSecurityRules] Adding NSG Rule Named: $($networkSecurityRuleConfig.Name) to NSG Named: $($nsg.Name)"
        $nsg | Add-AzNetworkSecurityRuleConfig @networkSecurityRuleConfig > $null
        $priorityCount++
    }

    # Adding NSG Rule for each inboundNAT Rule
    log -Message "[_AddLBNSGSecurityRules] Adding one NSG Rule for each inboundNatRule"
    $networkSecurityRuleConfig = $null
    $inboundNatRules = $BasicLoadBalancer.InboundNatRules
    foreach ($inboundNatRule in $inboundNatRules) {
        if ([string]::IsNullOrEmpty($inboundNatRule.FrontendPortRangeStart)) {
            $dstportrange = ($inboundNatRule.BackendPort).ToString()
        }
        else {
            $dstportrange = (($inboundNatRule.FrontendPortRangeStart).ToString() + "-" + ($inboundNatRule.FrontendPortRangeEnd).ToString())
        }
        $networkSecurityRuleConfig = @{
            Name                                = ($inboundNatRule.Name + "-NatRule")
            Protocol                            = $inboundNatRule.Protocol
            SourcePortRange                     = "*"
            DestinationPortRange                = $dstportrange
            SourceAddressPrefix                 = "*"
            DestinationAddressPrefix            = "*"
            SourceApplicationSecurityGroup      = $null
            DestinationApplicationSecurityGroup = $null
            Access                              = "Allow"
            Priority                            = $priorityCount
            Direction                           = "Inbound"
        }
        log -Message "[_AddLBNSGSecurityRules] Adding NSG Rule Named: $($networkSecurityRuleConfig.Name) to NSG Named: $($nsg.Name)"
        $nsg | Add-AzNetworkSecurityRuleConfig @networkSecurityRuleConfig > $null
        $priorityCount++
    }

    # Saving NSG
    log -Message "[_AddLBNSGSecurityRules] Saving NSG Named: $($nsg.Name)"
    try {
        $ErrorActionPreference = 'Stop'
        Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg > $null
    }
    catch {
        $message = "[NsgCreationVmss] An error occured while adding security rules to NSG '$($nsg.Name)'. TRAFFIC FROM LOAD BALANCER TO BACKEND POOL MEMBERS WILL BE BLOCKED UNTIL AN NSG WITH AN ALLOW RULE IS CREATED! To recover, manually rules in NSG '$("NSG-"+$vmss.Name)' which allows traffic to the backend ports on the VM/VMSS and associate the NSG with the VM, VMSS, or subnet. Error: $_ "
        log 'Error' $message -terminateOnError
    }
}

function _GetVMSSNSG {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] 
        $vmss,

        # skip logging - - used in validation
        [Parameter(Mandatory = $false)]
        [switch]
        $skipLogging
    )

    If ($skipLogging) {
        function log {}
    }

    $vmssHasNSG = $false

    # Check if VMSS already has a NSG
    # NOTE: this is not implemented, because if an NSG already existed, we assume the necessary traffic would already have been allowed
    log -Message "[NsgCreationVmss] Checking if VMSS Named: $($vmss.Name) has a NSG"
    if (![string]::IsNullOrEmpty($vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations.NetworkSecurityGroup)) {
        log -Message "[NsgCreationVmss] NSG detected in VMSS Named: $($vmss.Name) NetworkInterfaceConfigurations.NetworkSecurityGroup Id: $($vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations.NetworkSecurityGroup.Id)" -severity "Information"
        log -Message "[NsgCreationVmss] NSG will not be created for VMSS Named: $($vmss.Name)" -severity "Information"
        $vmssHasNSG = $true
    }

    # check vmss subnets for attached NSG's
    if (![string]::IsNullOrEmpty($vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations.Ipconfigurations.Subnet)) {
        $subnetIds = @($vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations.Ipconfigurations.Subnet.id)
        $found = $false

        foreach ($subnetId in $subnetIds) {
            $subnet = Get-AzResource -ResourceId $subnetId
            if (![string]::IsNullOrEmpty($subnet.Properties.NetworkSecurityGroup)) {
                log -Message "[NsgCreationVmss] NSG detected in Subnet for VMSS Named: $($vmss.Name) Subnet.NetworkSecurityGroup Id: $($subnet.Properties.NetworkSecurityGroup.Id)" -severity "Information"
                log -Message "[NsgCreationVmss] NSG will not be created for VMSS Named: $($vmss.Name)" -severity "Information"
                $found = $true
                break
            }
        }
        
        if ($found) { 
            $vmssHasNSG = $true
        }
    }

    return $vmssHasNSG
}

function _GetVMNSG {
    param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        # skip logging - - used in validation
        [Parameter(Mandatory = $false)]
        [switch]
        $skipLogging
    )

    If ($skipLogging) {
        function log {}
    }

    log -Message "[NsgCreationVM] Looping all VMs in the backend pool of the Load Balancer"
    $nicIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object { ($_ -split '/ipConfigurations/')[0].ToLower() } | Select-Object -Unique
    
    $joinedIPConfigIDs = ($BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | ForEach-Object { "'$_'" }) -join ','
    $joinedNicIDs = ($nicIDs | ForEach-Object { "'$_'" }) -join ','

    # NOTE: the resource graph data will lag behind ARM by a couple minutes, so creating resource and immediately 
    #   attempting migration (as in a test) will result in not ARG results. As a workaround, set the Environment Variable $env:LBMIG_WAIT_FOR_ARG = $true
    #

    $graphQuery = @"
    Resources |
        where type =~ 'microsoft.network/networkinterfaces' and id in~ ($joinedNicIDs) | 
        mv-expand ipConfigs = properties.ipConfigurations |
        project nicId = id,ipConfigs,nicNSGId=tostring(properties.networkSecurityGroup.id) |
        where ipConfigs.id in~ ($joinedIPConfigIDs) |
        extend nicAndNSGId=strcat(nicId,';',nicNSGId) |
        summarize nicRecords=make_set(nicAndNSGId) by subnetId = tolower(tostring(ipConfigs.properties.subnet.id)) |
        join ( Resources |
            where type =~ 'microsoft.network/virtualnetworks' |
            mv-expand subnets = properties.subnets |
            project subnetId=tolower(tostring(subnets.id)),subnetNSGId = tostring(subnets.properties.networkSecurityGroup.id)) on subnetId |
    project subnetId,nicRecords,subnetNSGId
"@

    log -Severity Verbose -Message "Graph Query Text: `n$graphQuery"
    $waitingForARG = $false
    $timeoutStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    do {        
        If (!$waitingForARG) {
            log -Message "[NsgCreationVM] Querying Resource Graph for current NIC and Subnet NSG associations..."
        }
        Else {
            log -Message "[NsgCreationVM] Waiting 15 seconds before querying ARG again..."
            Start-Sleep 15
        }

        $backendNICSubnets = Search-AzGraph -Query $graphQuery

        $waitingForARG = $true
    } while ($backendNICSubnets.count -eq 0 -and $env:LBMIG_WAIT_FOR_ARG -and $timeoutStopwatch.Elapsed.Minutes -lt 15)

    If ($timeoutStopwatch.Elapsed.Minutes -gt 15) {
        log -Severity Error -Message "[NsgCreationVM] Resource Graph query timed out before results were returned! The Resource Graph lags behind ARM by several minutes--if the resources to migrate were just created (as in a test), test the query from the log to determine if this was an ingestion lag or synax failure. Once the issue has been corrected, follow the documented migration recovery steps here: https://learn.microsoft.com/azure/load-balancer/upgrade-basic-standard-virtual-machine-scale-sets#what-happens-if-my-upgrade-fails-mid-migration" -terminateOnError
    }

    log -Message "[NsgCreationVM] Found '$($backendNICSubnets.count)' subnets associcated with VMs in the Basic LB's backend pool."
    
    log -Message "[NsgCreationVM] Checking NSGs to update or create based on Resource Graph data..."
    $nsgIDsToUpdate = @()
    $nicsNeedingNewNSG = @()
    ForEach ($subnetRecord in $backendNICSubnets) {
        
        # if nic subnet has an NSG, plan to add a rule to that NSG
        log -Message "[NsgCreationVM] Checking for existing NSGs at the subnet (it is assumed if an NSG exists, it allows LB traffic already)"
        If ($subnetRecord.subnetNSGId) {
            log -Message "[NsgCreationVM] NSG found on subnet '$($subnetId)', NSG: '$($subnetNSGId)'"
            $nsgIDsToUpdate += $subnetRecord.subnetNSGId
        }
        Else {
            log -Message "[NsgCreationVM] Checking for existing NSGs at the NICs (it is assumed if an NSG exists, it allows LB traffic already)"
            ForEach ($nicRecord in $subnetRecord.nicRecords) {
                $nicId, $nicNSGId = $nicRecord.split(';')

                # if there is no subnet level nsg, but there is a NIC-level NSG, plan to add a rule to that NSG
                If (![string]::IsNullOrEmpty($nicNSGId)) {
                    log -Message "[NsgCreationVM] Existing NSG found for NIC '$($nicId)', NSG: '$($nicNSGId)'"
                    $nsgIDsToUpdate += $nicNSGId
                }
                # if there is no NIC or Subnet NSG, plan to create a new one for the NIC
                Else {
                    log -Message "[NsgCreationVM] No NSG found for NIC '$($nicId)' at the NIC or Subnet level, will create and assiciate new NSG"
                    $nicsNeedingNewNSG += $nicId
                }
            }
        }
    }

    return $nicsNeedingNewNSG, $nsgIDsToUpdate
}

function NsgCreationVmss {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[NsgCreationVmss] Initiating NSG Creation for VMSS"

    log -Message "[NsgCreationVmss] Looping all VMSS in the backend pool of the Load Balancer"
    $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object { ($_ -split '/virtualMachines/')[0].ToLower() } | Select-Object -Unique    
    
    foreach ($vmssId in $vmssIds) {
        $vmss = Get-AzResource -ResourceId $vmssId | Get-AzVmss

        log -Message "[NSGCreationVmss] Checking if VMSS $($vmss.Name) has a NSG"

        $vmssHasNSG = _GetVMSSNSG -vmss $vmss
        
        If (!$vmssHasNSG) {
            log -Message "[NsgCreationVmss] NSG not detected."

            log -Message "[NsgCreationVmss] Creating NSG for VMSS: '$($vmss.Name)'"

            try {
                $ErrorActionPreference = 'Stop'
                $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $vmss.ResourceGroupName -Name ("nsg-" + $vmss.Name) -Location $vmss.Location -Force
            }
            catch {
                $message = "[NsgCreationVmss] An error occured while creating NSG '$("nsg-"+$vmss.Name)'. TRAFFIC FROM LOAD BALANCER TO BACKEND POOL MEMBERS WILL BE BLOCKED UNTIL AN NSG WITH AN ALLOW RULE IS CREATED! To recover, manually create an NSG which allows traffic to the backend ports on the VM/VMSS and associate it with the VM, VMSS, or subnet. Error: $_"
                log 'Error' $message -terminateOnError
            }

            log -Message "[NsgCreationVmss] NSG Named: $("nsg-"+$vmss.Name) created."

            _AddLBNSGSecurityRules -BasicLoadBalancer $BasicLoadBalancer -nsg $nsg

            # Adding NSG to VMSS
            log -Message "[NsgCreationVmss] Adding NSG Named: $($nsg.Name) to VMSS Named: $($vmss.Name)"
            foreach ($networkInterfaceConfiguration in $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
                $networkInterfaceConfiguration.NetworkSecurityGroup = $nsg.Id
            }

            # Saving VMSS
            log -Message "[NsgCreationVmss] Saving VMSS Named: $($vmss.Name)"
            try {
                $ErrorActionPreference = 'Stop'
                $job = Update-AzVmss -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name -VirtualMachineScaleSet $vmss -AsJob

                While ($job.State -eq 'Running') {
                    Start-Sleep -Seconds 15
                    log -Message "[NsgCreationVmss] Waiting for updating VMSS job (id: '$($job.id)') to complete..."
                }
    
                If ($job.Error -or $job.State -eq 'Failed') {
                    Write-Error $job.error
                }
            }
            catch {
                $message = "[NsgCreationVmss] An error occured while updating VMSS '$($vmss.name)' to associate the new NSG '$("NSG-"+$vmss.Name)'. TRAFFIC FROM LOAD BALANCER TO BACKEND POOL MEMBERS WILL BE BLOCKED UNTIL AN NSG WITH AN ALLOW RULE IS CREATED! To recover, manually associate NSG '$("NSG-"+$vmss.Name)' with the VM, VMSS, or subnet. Error: $_"
                log 'Error' $message -terminateOnError
            }

            UpdateVmssInstances -vmss $vmss

            log -Message "[NsgCreationVmss] NSG Creation Completed"
        }
        Else {
            log -Message "[NsgCreationVmss] NSG creation skipped because VMSS already has an associated"
        }
    }

    log -Message "[NsgCreationVmss] Completing NSG Creation for VMSS LB"
}

function NsgCreationVM {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[NsgCreationVM] Initiating NSG Creation for VMs"

    $nicsNeedingNewNSG, $nsgIDsToUpdate = _GetVMNSG -BasicLoadBalancer $BasicLoadBalancer

    log -Message "[NsgCreationVM] Updating existing NSGs with new security rules for the LB..."
    # add security rule to existing NSGs ensuring LB traffic is allowed
    # NOTE: this is not implemented, because if an NSG already existed, we assume the necessary traffic would already have been allowed
    Foreach ($nsgId in $nsgIDsToUpdate) {
        log -Severity Warning -Message "[NsgCreationVM] Updating exising NSGs is not implemented; ensure your NSG '$nsgId' has rules to allow traffic from the Load Balancer!"
        #_AddLBNSGSecurityRules -BasicLoadBalancer $BasicLoadBalancer -nsgId $nsgId
    }

    # create new NSGs and associate with NICs
    If ($nicsNeedingNewNSG.count -gt 0) {
        log -Message "[NsgCreationVM] Creating a new NSG with new security rules for the LB to associate to NICs missing NSGs..."

        $nsgName = "nsg-lbmigration-$($BasicLoadBalancer.Name)"

        log -Message "[NsgCreationVM] Creating a new NSG named '$nsgName' in Resource Group '$($BasicLoadBalancer.ResourceGroupName)'..."
        $newNicLevelNSG = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $BasicLoadBalancer.ResourceGroupName -Location $BasicLoadBalancer.Location

        log -Message "[NsgCreationVM] Adding security rules to new NSG '$nsgName'"
        _AddLBNSGSecurityRules -BasicLoadBalancer $BasicLoadBalancer -nsg $newNicLevelNSG
        
        log -Message "[NsgCreationVM] Associating new NSG '$nsgName' with NICs missing NSGs"
        $nicNSGUpdateJobs = @()
        ForEach ($nicId in $nicsNeedingNewNSG) {
            $nic = Get-AzNetworkInterface -ResourceId $nicId

            log -Message "[NsgCreationVM] Associating new NSG '$nsgName' with NIC '$($nic.id)'"
            $nic.NetworkSecurityGroup = @{ id = $newNicLevelNSG.id }

            $nicNSGUpdateJobs += $nic | Set-AzNetworkInterface -AsJob
        }

        $nicNSGUpdateJobs | Wait-Job -Timeout $defaultJobWaitTimeout | Foreach-Object {
            $job = $_
            If ($job.Error -or $job.State -eq 'Failed') {
                log -Severity Error -Message "Associating NIC to new NSG failed with error: $($job.error; $job | Receive-Job). Migration will continue--to recover, manually associate NICs with the NSG '$($newNicLevelNSG.Id)' after the script completes."
            }
        }
    }

    log -Message "[NsgCreationVM] NSG Creation Completed"
}

Export-ModuleMember -Function NsgCreationVmss, NsgCreationVM, _GetVMNSG, _GetVMSSNSG
