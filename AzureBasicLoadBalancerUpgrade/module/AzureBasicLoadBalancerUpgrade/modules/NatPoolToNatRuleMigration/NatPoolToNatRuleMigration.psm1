Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/UpdateVmssInstances/UpdateVmssInstances.psd1")
Function Start-NatPoolToNatRuleMigration {
    <#
.SYNOPSIS
    Migrates an Azure Standard Load Balancer's Inbound NAT Pools to Inbound NAT Rules
.DESCRIPTION
    This script creates a new NAT Rule for each NAT Pool, then adds a new Backend Pool with membership corresponding to the NAT Pool's original membership. 

    For every NAT Pool, a new NAT Rule and backend pool will be created on the Load Balancer. Names will follow these patterns:
        natrule_migrated_<inboundNATPool Name>
        be_migrated_<inboundNATPool Name>

    The script reassociated NAT Pool VMSSes with the new NAT Rules, requiring multiple updates to the VMSS model and instance upgrades, which may cause service disruption during the migration. 

    Backend port mapping for pool members will not necessarily be the same for NAT Pools with multiple associated VMSSes. 
.NOTES
    Please report issues at: https://github.com/Azure/AzLoadBalancerMigration/issues

.LINK
    https://github.com/Azure/AzLoadBalancerMigration
    
.EXAMPLE
    Import-Module AzureLoadBalancerNATPoolMigration
    Start-NatPoolToNatRuleMigration -LoadBalancerName lb-standard-01 -verbose -ResourceGroupName rg-natpoollb
    
    # Migrates all NAT Pools on Load Balance 'lb-standard-01' to new NAT Rules. 

.EXAMPLE
    Import-Module AzureLoadBalancerNATPoolMigration
    $lb = Get-AzLoadBalancer | ? name -eq 'my-standard-lb-01'
    $lb | Start-NatPoolToNatRuleMigration -LoadBalancerName lb-standard-01 -verbose -ResourceGroupName rg-natpoollb
    
    # Migrates all NAT Pools on Load Balance 'lb-standard-01' to new NAT Rules, passing the Load Balancer to the function through the pipeline. 
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True, ValueFromPipeline, ParameterSetName = 'ByObject')][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $basicLoadBalancer,
        [Parameter(Mandatory = $True, ValueFromPipeline, ParameterSetName = 'ByObject')][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $standardLoadBalancer
    )

    Function Wait-VMSSInstanceUpdate {
        [CmdletBinding()]
        param (
            [Parameter()]
            [Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet]
            $vmss
        )

        $vmssInstances = Get-AzVmssVM -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name

        If ($vmssInstances.LatestModelApplied -contains $false) {
            log -message "[Start-NatPoolToNatRuleMigration] `tWaiting for VMSS '$($vmss.Name)' to update all instances..."
            Start-Sleep -Seconds 15
            Wait-VMSSInstanceUpdate -vmss $vmss
        }
    }

    $ErrorActionPreference = 'Stop'

    log -message "[Start-NatPoolToNatRuleMigration] Starting NAT Pool to NAT Rule migration..."

    # check load balancer sku
    If ($standardLoadBalancer.sku.name -ne 'Standard') {
        log -Severity Error -terminateOnError -message "[Start-NatPoolToNatRuleMigration] In order to migrate to NAT Rules, the Load Balancer must be a Standard SKU. Upgrade the Load Balancer first. See: https://learn.microsoft.com/azure/load-balancer/load-balancer-basic-upgrade-guidance"
    }

    # check load balancer has inbound nat pools
    If ($basicLoadBalancer.InboundNatPools.count -lt 1) {
        log -message "[Start-NatPoolToNatRuleMigration] Load Balancer '$($basicLoadBalancer.Name)' does not have any Inbound NAT Pools to migrate"
        return
    }

    # create a hard copy of NAT Pool configs for later reference
    $inboundNatPoolConfigs = $basicLoadBalancer.InboundNatPools | ConvertTo-Json | ConvertFrom-Json

    try {
        $ErrorActionPreference = 'Stop'

        # get add virtual machine scale sets associated with the LB NAT Pools (via NAT Pool-create NAT Rules)
        $vmssIds = $basicLoadBalancer.InboundNatRules.BackendIPConfiguration.Id | Foreach-Object { ($_ -split '/virtualMachines/')[0].ToLower() } | Select-Object -Unique

        If (![string]::IsNullOrEmpty($vmssIds)) {
            log -message "[Start-NatPoolToNatRuleMigration] The following VMSSes are associated with the NAT Pools: $($vmssIds -join ', ')"

            $vmssObjects = $vmssIds | ForEach-Object { Get-AzResource -ResourceId $_ | Get-AzVmss }

            # build vmss table
            $vmsses = @()
            ForEach ($vmss in $vmssObjects) {
                $vmsses += @{
                    vmss           = $vmss
                    updateRequired = $false
                }
            }
        }
    }
    catch {
        log -Severity Error -message "[Start-NatPoolToNatRuleMigration] An error occured while getting the VMSSes associated with the NAT Pools. Migration will continue. If VMSSes were associated with NAT Pools, they will need to be manually reassociated post-migration!: $_"
    }

    # check that vmsses use Manual or Automatic upgrade policy
    $incompatibleUpgradePolicyVMSSes = $vmsses.vmss | Where-Object { $_.UpgradePolicy.Mode -notIn 'Manual', 'Automatic' }
    If ($incompatibleUpgradePolicyVMSSes.count -gt 0) {
        log -Severity Error -terminateOnError -message "[Start-NatPoolToNatRuleMigration] The following VMSSes have upgrade policies which are not Manual or Automatic: $($incompatibleUpgradePolicyVMSSes.id)"
    }

    try {
        log -Message "[Start-NatPoolToNatRuleMigration] Starting adding new NAT Rules and Backend Pools to load balancer..."

        $ErrorActionPreference = 'Stop'

        # update load balancer with nat rule configurations
        $natPoolToBEPMap = @{} # { natPoolId = backendPoolId, ... } 
        ForEach ($inboundNATPool in $inboundNatPoolConfigs) {

            # add a new backend pool for the NAT rule
            $newBackendPoolName = "be_migrated_$($inboundNATPool.Name)"

            log -message "[Start-NatPoolToNatRuleMigration] Adding new Backend Pool '$newBackendPoolName' to LB for NAT Pool '$($inboundNATPool.Name)'"
            $standardLoadBalancer = $standardLoadBalancer | Add-AzLoadBalancerBackendAddressPoolConfig -Name $newBackendPoolName
            $natPoolToBEPMap[$inboundNATPool.Id] = '{0}/backendAddressPools/{1}' -f $standardLoadBalancer.Id, $newBackendPoolName

            # update the load balancer config
            $standardLoadBalancer = $standardLoadBalancer | Set-AzLoadBalancer 

            # add a NAT rule config
            $frontendIPConfiguration = New-Object Microsoft.Azure.Commands.Network.Models.PSFrontendIPConfiguration
            $frontendIPConfiguration.id = $inboundNATPool.FrontendIPConfiguration.Id -replace $basicLoadBalancer.Id, $standardLoadBalancer.Id

            $backendAddressPool = $standardLoadBalancer.BackendAddressPools | Where-Object { $_.name -eq $newBackendPoolName }

            $newNatRuleName = "natrule_migrated_$($inboundNATPool.Name)"

            log -message "[Start-NatPoolToNatRuleMigration] Adding new NAT Rule '$newNatRuleName' to LB..."
            $standardLoadBalancer = $standardLoadBalancer | Add-AzLoadBalancerInboundNatRuleConfig -Name $newNatRuleName `
                -Protocol $inboundNATPool.Protocol `
                -FrontendPortRangeStart $inboundNATPool.FrontendPortRangeStart `
                -FrontendPortRangeEnd $inboundNATPool.FrontendPortRangeEnd `
                -BackendPort $inboundNATPool.BackendPort `
                -FrontendIpConfiguration $frontendIPConfiguration `
                -BackendAddressPool $backendAddressPool

            # update the load balancer config
            $standardLoadBalancer = $standardLoadBalancer | Set-AzLoadBalancer
        }

        log -Message "[Start-NatPoolToNatRuleMigration] Finished adding new NAT Rules and Backend Pools to load balancer."
    }
    catch {
        log -Severity Error -Message "[Start-NatPoolToNatRuleMigration] An error occured while updating the Load Balancer with new NAT Rules and additional Backend Pools. To recover, address the cause of the following error, then follow the steps at https://aka.ms/basiclbupgradefailure to retry the migration. Error: $_" -terminateOnError
    }

    If ($vmsses) {
        # add vmss model ip configs to new backend pools
        log -message "[Start-NatPoolToNatRuleMigration] Adding new backend pools to VMSS model ipConfigs..."

        try {
            $ErrorActionPreference = 'Stop'
            ForEach ($vmssItem in $vmsses) {
                ForEach ($nicConfig in $vmssItem.vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
                    ForEach ($ipConfig in $nicConfig.ipConfigurations) {
                
                        # if there is an existing ipconfig to nat pool association, add the ipconfig to the new backend pool for the nat rule
                        If ($ipconfigRecord = $ipConfigNatPoolMap | Where-Object {
                                $_.vmssId -eq $vmssItem.vmss.id -and
                                $_.nicName -eq $nicConfig.Name -and
                                $_.ipConfigName -eq $ipConfig.Name
                            }) {

                            #$backendPoolList = New-Object System.Collections.Generic.List[Microsoft.Azure.Commands.Network.Models.PSBackendAddressPool]
                            $backendPoolList = New-Object System.Collections.Generic.List[Microsoft.Azure.Management.Compute.Models.SubResource]

                            # add existing backend pools to pool list to maintain existing membership
                            ForEach ($existingBackendPoolId in $ipConfig.LoadBalancerBackendAddressPools.id) {
                                $backendPoolObj = new-object Microsoft.Azure.Management.Compute.Models.SubResource
                                $backendPoolObj.id = $existingBackendPoolId

                                $backendPoolList.Add($backendPoolObj)
                            }
                            #$backendPoolObj = new-object Microsoft.Azure.Commands.Network.Models.PSBackendAddressPool
                            $backendPoolObj = New-Object Microsoft.Azure.Management.Compute.Models.SubResource
                            $backendPoolObj.id = $natPoolToBEPMap[$ipconfigRecord.inboundNatPoolId]

                            log -message "[Start-NatPoolToNatRuleMigration] Adding VMSS '$($vmssItem.vmss.Name)' NIC '$($nicConfig.Name)' ipConfig '$($ipConfig.Name)' to new backend pool '$($backendPoolObj.id)'"
                            $backendPoolList.Add($backendPoolObj)

                            $ipConfig.LoadBalancerBackendAddressPools = $backendPoolList

                            $vmssItem.updateRequired = $true
                        }
                    }
                }
            }

            # update each vmss to add the backend pool membership to the model
            $vmssModelUpdateAddBackendPoolJobs = @()
            ForEach ($vmssItem in ($vmsses | Where-Object { $_.updateRequired })) {
                $vmss = $vmssItem.vmss
                $job = $vmss | Update-AzVmss -AsJob
                $job.Name = $vmss.vmss.Name + '_modelUpdateAddBackendPool'
                $vmssModelUpdateAddBackendPoolJobs += $job
            }

            log -message "[Start-NatPoolToNatRuleMigration] Waiting for VMSS model to update to include the new Backend Pools..."
            While ($vmssModelUpdateAddBackendPoolJobs.State -contains 'Running') {
                Start-Sleep -Seconds 15
                log -message "[Start-NatPoolToNatRuleMigration] `t[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:sszz')]Waiting for VMSS model update jobs to complete..."
            } 
    
            $vmssModelUpdateAddBackendPoolJobs | Foreach-Object {
                $job = $_
                If ($job.Error -or $job.State -eq 'Failed') {
                    log -Severity Error -terminateOnError -message "[Start-NatPoolToNatRuleMigration] An error occured while updating the VMSS model to add the NAT Rules: $($job.error; $job | Receive-Job)."
                }
            }
 
            # update all vmss instances to include the backend pool
            log -message "[Start-NatPoolToNatRuleMigration] Waiting for VMSS instances to update to include the new Backend Pools..."
            $vmssInstanceUpdateAddBackendPoolJobs = @()
            ForEach ($vmssItem in ($vmsses | Where-Object { $_.updateRequired })) {

                If ($vmss.UpgradePolicy.Mode -eq 'Automatic') {
                    Wait-VMSSInstanceUpdate -vmss $vmss
                }
                Else {
                    $vmss = $vmssItem.vmss
                    $vmssInstances = Get-AzVmssVM -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name

                    $job = Update-AzVmssInstance -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name -InstanceId $vmssInstances.InstanceId -AsJob
                    $job.Name = $vmss.vmss.Name + '_instanceUpdateAddBackendPool'
                    $vmssInstanceUpdateAddBackendPoolJobs += $job
                }
            }

            # for manual update vmsses, wait for the instance update jobs to complete
            If ($vmssInstanceUpdateAddBackendPoolJobs.count -gt 0) {
                $vmssInstanceUpdateAddBackendPoolJobs | Wait-Job | Foreach-Object {
                    $job = $_
                    If ($job.Error -or $job.State -eq 'Failed') {
                        log -Severity Error -terminateOnError -message "[Start-NatPoolToNatRuleMigration] An error occured while updating the VMSS instanaces to add the NAT Rules: $($job.error; $job | Receive-Job)."
                    }
                }
            }
        }
        catch {
            log -Severity Error -message "[Start-NatPoolToNatRuleMigration] An error occured while updating the VMSS model to add the new Backend Pools. Migration will attempt to continue; if successful, VMSSes will need to be manually associated with new NAT Rules. If continuing fails, address the cause of the following error, then follow the steps at https://aka.ms/basiclbupgradefailure to retry the migration.: $_"
        }
    }
    Else {
        log -message "[Start-NatPoolToNatRuleMigration] No VMSSes are associated with the NAT Pools, migrated as empty"
    }

    log -Message "[Start-NatPoolToNatRuleMigration] NAT Pool to NAT Rule migration complete."
}

Export-ModuleMember -Function Start-NatPoolToNatRuleMigration 