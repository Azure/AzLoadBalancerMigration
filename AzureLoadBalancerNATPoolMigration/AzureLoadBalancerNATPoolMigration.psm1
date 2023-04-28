
Function Start-AzNATPoolMigration {
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
    Start-AzNatPoolMigration -LoadBalancerName lb-standard-01 -verbose -ResourceGroupName rg-natpoollb
    
    # Migrates all NAT Pools on Load Balance 'lb-standard-01' to new NAT Rules. 

.EXAMPLE
    Import-Module AzureLoadBalancerNATPoolMigration
    $lb = Get-AzLoadBalancer | ? name -eq 'my-standard-lb-01'
    $lb | Start-AzNatPoolMigration -LoadBalancerName lb-standard-01 -verbose -ResourceGroupName rg-natpoollb
    
    # Migrates all NAT Pools on Load Balance 'lb-standard-01' to new NAT Rules, passing the Load Balancer to the function through the pipeline. 
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True, ParameterSetName = 'ByName')][string] $ResourceGroupName,
        [Parameter(Mandatory = $True, ParameterSetName = 'ByName')][string] $LoadBalancerName,
        [Parameter(Mandatory = $True, ValueFromPipeline, ParameterSetName = 'ByObject')][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $LoadBalancer
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
            Write-Host "`tWaiting for VMSS '$($vmss.Name)' to update all instances..."
            Start-Sleep -Seconds 5
            Wait-VMSSInstanceUpdate -vmss $vmss
        }
    }

    $ErrorActionPreference = 'Stop'

    # get load balanacer if not passed through pipeline
    try {
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $LoadBalancer = Get-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $LoadBalancerName
        }
    }
    catch {
        Write-Error "Failed to find Load Balancer '$LoadBalancerName' in Resource Group '$ResourceGroupName'. Ensure that the name values are correct and that you have appropriate permissions."
    }

    # check load balancer sku
    If ($LoadBalancer.sku.name -ne 'Standard') {
        Write-Error "In order to migrate to NAT Rules, the Load Balancer must be a Standard SKU. Upgrade the Load Balancer first. See: https://learn.microsoft.com/azure/load-balancer/load-balancer-basic-upgrade-guidance"
    }

    # check load balancer has inbound nat pools
    If ($LoadBalancer.InboundNatPools.count -lt 1) {
        Write-Error "Load Balancer '$($loadBalancer.Name)' does not have any Inbound NAT Pools to migrate"
    }

    # create a hard copy of NAT Pool configs for later reference
    $inboundNatPoolConfigs = $LoadBalancer.InboundNatPools | ConvertTo-Json | ConvertFrom-Json

    # get add virtual machine scale sets associated with the LB NAT Pools (via NAT Pool-create NAT Rules)
    If (!$LoadBalancer.InboundNatRules) {
        Write-Error "Load Balancer '$($loadBalancer.Name)' does not have any Inbound NAT Rules. This is unexpected. NAT Rules are created automatically when the VMSS Network Profile is updated to include an Inbound NAT Pool and the VMSS instances are updated with the VMSS mode."
    }
    $vmssIds = $LoadBalancer.InboundNatRules.BackendIpConfiguration.id | Foreach-Object { ($_ -split '/virtualMachines/')[0].ToLower() } | Select-Object -Unique
    If ($vmssIds.count -lt 1) {
        # this error should not be hit... but just in case
        Write-Error "Load Balancer '$($loadBalancer.Name)' does not have any VMSSes associated with its NAT Pools."
    }
    $vmssObjects = $vmssIds | ForEach-Object { Get-AzResource -ResourceId $_ | Get-AzVmss }

    # build vmss table
    $vmsses = @()
    ForEach ($vmss in $vmssObjects) {
        $vmsses += @{
            vmss           = $vmss
            updateRequired = $false
        }
    }

    # check that vmsses use Manual or Automatic upgrade policy
    $incompatibleUpgradePolicyVMSSes = $vmsses.vmss | Where-Object { $_.UpgradePolicy.Mode -notIn 'Manual', 'Automatic' }
    If ($incompatibleUpgradePolicyVMSSes.count -gt 0) {
        Write-Error "The following VMSSes have upgrade policies which are not Manual or Automatic: $($incompatibleUpgradePolicyVMSSes.id)"
    }

    # remove each vmss model's ipconfig from the load balancer's inbound nat pool
    Write-Host "Removing the NAT Pool from the VMSS model ipConfigs."
    $ipConfigNatPoolMap = @()
    ForEach ($inboundNATPool in $LoadBalancer.InboundNatPools) {
        ForEach ($vmssItem in $vmsses) {
            ForEach ($nicConfig in $vmssItem.vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
                ForEach ($ipConfig in $nicConfig.ipConfigurations) {
                    If ($ipConfig.loadBalancerInboundNatPools.id -contains $inboundNATPool.id) {

                        Write-Host "Removing NAT Pool '$($inboundNATPool.id)' from VMSS '$($vmssItem.vmss.Name)' NIC '$($nicConfig.Name)' ipConfig '$($ipConfig.Name)'"
                        $ipConfigParams = @{vmssId = $vmssItem.vmss.id; nicName = $nicConfig.Name; ipconfigName = $ipConfig.Name; inboundNatPoolId = $inboundNatPool.id }
                        $ipConfigNatPoolMap += $ipConfigParams
                        $ipConfig.loadBalancerInboundNatPools = $ipConfig.loadBalancerInboundNatPools | Where-Object { $_.id -ne $inboundNATPool.Id }

                        $vmssItem.updateRequired = $true
                    }
                }
            }
        }
    }

    # update each vmss to remove the nat pools from the model
    $vmssModelUpdateRemoveNATPoolJobs = @()
    ForEach ($vmssItem in ($vmsses | Where-Object { $_.updateRequired })) {
        $vmss = $vmssItem.vmss
        $job = $vmss | Update-AzVmss -AsJob
        $job.Name = $vmss.vmss.Name + '_modelUpdateRemoveNATPool'
        $vmssModelUpdateRemoveNATPoolJobs += $job
    }

    Write-Host "Waiting for VMSS model to update to remove the NAT Pool references..."
    $vmssModelUpdateRemoveNATPoolJobs | Wait-Job | Foreach-Object {
        $job = $_
        If ($job.Error -or $job.State -eq 'Failed') {
            Write-Error "An error occured while updating the VMSS model to remove the NAT Pools: $($job.error; $job | Receive-Job)."
        }
    }

    # update all vmss instances
    Write-Host "Updating VMSS instances to remove the NAT Pool references..."
    $vmssInstanceUpdateRemoveNATPoolJobs = @()
    ForEach ($vmssItem in ($vmsses | Where-Object { $_.updateRequired })) {
        $vmss = $vmssItem.vmss

        If ($vmss.UpgradePolicy.Mode -eq 'Automatic') {
            Wait-VMSSInstanceUpdate -vmss $vmss
        }
        Else {
            $vmssInstances = Get-AzVmssVM -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name

            $job = Update-AzVmssInstance -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name -InstanceId $vmssInstances.InstanceId -AsJob
            $job.Name = $vmss.vmss.Name + '_instanceUpdateRemoveNATPool'
            $vmssInstanceUpdateRemoveNATPoolJobs += $job
        }
    }

    # for manual update vmsses, wait for the instance update jobs to complete
    If ($vmssInstanceUpdateRemoveNATPoolJobs.count -gt 0) {
        Write-Host "`tWaiting for VMSS instances to update to remove the NAT Pool references..."
        $vmssInstanceUpdateRemoveNATPoolJobs | Wait-Job | Foreach-Object {
            $job = $_
            If ($job.Error -or $job.State -eq 'Failed') {
                Write-Error "An error occured while updating the VMSS instances to remove the NAT Pools: $($job.error; $job | Receive-Job)."
            }
        }
    }

    # remove all NAT pools to avoid port conflicts with NAT rules
    $LoadBalancer.InboundNatPools = $null

    # update the load balancer config
    $LoadBalancer = $LoadBalancer | Set-AzLoadBalancer 

    # update load balancer with nat rule configurations
    $natPoolToBEPMap = @{} # { natPoolId = backendPoolId, ... } 
    ForEach ($inboundNATPool in $inboundNatPoolConfigs) {

        # add a new backend pool for the NAT rule
        $newBackendPoolName = "be_migrated_$($inboundNATPool.Name)"

        Write-Host "Adding new Backend Pool '$newBackendPoolName' to LB for NAT Pool '$($inboundNATPool.Name)'"
        $LoadBalancer = $LoadBalancer | Add-AzLoadBalancerBackendAddressPoolConfig -Name $newBackendPoolName
        $natPoolToBEPMap[$inboundNATPool.Id] = '{0}/backendAddressPools/{1}' -f $LoadBalancer.Id, $newBackendPoolName

        # update the load balancer config
        $LoadBalancer = $LoadBalancer | Set-AzLoadBalancer 

        # add a NAT rule config
        $frontendIPConfiguration = New-Object Microsoft.Azure.Commands.Network.Models.PSFrontendIPConfiguration
        $frontendIPConfiguration.id = $inboundNATPool.FrontendIPConfiguration.Id

        $backendAddressPool = $LoadBalancer.BackendAddressPools | Where-Object { $_.name -eq $newBackendPoolName }

        $newNatRuleName = "natrule_migrated_$($inboundNATPool.Name)"

        Write-Host "Adding new NAT Rule '$newNatRuleName' to LB..."
        $LoadBalancer = $LoadBalancer | Add-AzLoadBalancerInboundNatRuleConfig -Name $newNatRuleName `
            -Protocol $inboundNATPool.Protocol `
            -FrontendPortRangeStart $inboundNATPool.FrontendPortRangeStart `
            -FrontendPortRangeEnd $inboundNATPool.FrontendPortRangeEnd `
            -BackendPort $inboundNATPool.BackendPort `
            -FrontendIpConfiguration $frontendIPConfiguration `
            -BackendAddressPool $backendAddressPool

        # update the load balancer config
        $LoadBalancer = $LoadBalancer | Set-AzLoadBalancer

    }

    # add vmss model ip configs to new backend pools
    Write-Host "Adding new backend pools to VMSS model ipConfigs..."

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

                    Write-Host "Adding VMSS '$($vmssItem.vmss.Name)' NIC '$($nicConfig.Name)' ipConfig '$($ipConfig.Name)' to new backend pool '$($backendPoolObj.id)'"
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

    Write-Host "Waiting for VMSS model to update to include the new Backend Pools..."
    $vmssModelUpdateAddBackendPoolJobs | Wait-Job | Foreach-Object {
        $job = $_
        If ($job.Error -or $job.State -eq 'Failed') {
            Write-Error "An error occured while updating the VMSS model to add the NAT Rules: $($job.error; $job | Receive-Job)."
        }
    }
 

    # update all vmss instances to include the backend pool
    Write-Host "Waiting for VMSS instances to update to include the new Backend Pools..."
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
                Write-Error "An error occured while updating the VMSS instanaces to add the NAT Rules: $($job.error; $job | Receive-Job)."
            }
        }
    }
}

Export-ModuleMember -Function Start-AzNATPoolMigration 