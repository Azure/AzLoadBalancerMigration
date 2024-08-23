
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

.PARAMETER backendPoolReuseStrategy
    This parameter controls whether new backend pools are created for each NAT Pool or if existing backend pools with the same membership as the NAT Pool will be reused. Possible values (stratgies) are:

    'FirstMatch': This is the default. The script will reuse the first backend pool with the same membership as the NAT Pool. If no matching backend pool is found, the script will exit. Use one of 
                  the other strategies or create a new backend pool and try again. If you have more than one backend pool with matching membership, you can use the -manualBackendPoolMap parameter to
                  specify which backend pool to use for a NAT Pool.
    'OptionalFirstMatch': The script will reuse the first backend pool with the same membership as the NAT Pool. If no matching backend pool is found, the script will create a new backend pool.
    'NoReuse': The script will create a new backend pool for each NAT Pool.

    To manually associate NAT pools with backend Pools, modify the -natPoolToBEPMap hashtable in the script.

.PARAMETER manualBackendPoolMap
    Use this parameter to override the backend pool reuse strategy and manually map the new NAT Rules created for NAT Pools to Backend Pools. The hashtable should be in the format:
        @{ 'natPoolId' = 'backendPoolId'; ... }

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
        [Parameter(Mandatory = $True, ValueFromPipeline, ParameterSetName = 'ByObject')][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $LoadBalancer,
        [Parameter(Mandatory = $false)]
        [ValidateSet('NoReuse', 'FirstMatch', 'OptionalFirstMatch')]
        [string] 
        $backendPoolReuseStrategy = 'FirstMatch', # see parameter help for details
        [Parameter(Mandatory = $false)][hashtable] $manualBackendPoolMap = @{}, # specify a manual mapping of NAT Pools to Backend Pools
        [Parameter(Mandatory = $false)][switch] $validateOnly # specify if the script should only validate the Load Balancer and VMSS configurations
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
            Start-Sleep -Seconds 15
            Wait-VMSSInstanceUpdate -vmss $vmss
        }
    }
Function Get-NATToBackendPoolMap {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $LoadBalancer,
        [Parameter(Mandatory = $True)][hashtable] $natPoolToBEPMap,
        [Parameter(Mandatory = $True)][string] $backendPoolReuseStrategy
    )

    Write-Verbose "Getting NAT Pool to Backend Pool mapping for Load Balancer '$($LoadBalancer.Name)'..."
    
    # get all ip configurations associated with the load balancer backend address pools
    $backendPoolIpConfigQuery = @"
        resources
        | where id =~ '$($LoadBalancer.id)' 
        | project id,backendPools = properties.backendAddressPools
        | mv-expand backendPool = backendPools
        | extend backendPoolId = tostring(backendPool.id)
        | project backendPoolId,loadBalancerId=id
        | join ( 
        resources
        | where type == 'microsoft.compute/virtualmachinescalesets'
        | project id,nicConfigs = properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations
        | where nicConfigs has '$($LoadBalancer.id)'
        | mv-expand nicConfig = nicConfigs
        | mv-expand ipConfig = nicConfig.properties.ipConfigurations
        | extend constructedIpConfigId = strcat(id,'/_nicConfigs/_',nicConfig.name,'/_ipConfig/_',ipConfig.name)
        | mv-expand associatedBackendPool = ipConfig.properties.loadBalancerBackendAddressPools
        | extend backendPoolId = tostring(associatedBackendPool.id)
        | project vmssId=id,backendPoolId,ipConfigId=tostring(constructedIpConfigId)
        | union ( 
            resources
            | where type == 'microsoft.network/networkinterfaces'
            | where properties.ipConfigurations has '$($LoadBalancer.id)'
            | mv-expand ipConfig = properties.ipConfigurations
            | mv-expand associatedBackendPool = ipConfig.properties.loadBalancerBackendAddressPools
            | extend backendPoolId = tostring(associatedBackendPool.id)
            | project nicId=id,backendPoolId,ipConfigId=tostring(ipConfig.id)
            )
        ) on backendPoolId
        | project-away backendPoolId1
        | summarize backendPoolMembers = make_set(ipConfigId) by backendPoolId,loadBalancerId
"@

    $backendPoolIpConfigs = Search-ResourceGraph -graphQuery $backendPoolIpConfigQuery

    # get all ip configurations associated with the load balancer inbound nat pools
    $natPoolIpConfigQuery = @"
        resources
        | where id =~ '$($LoadBalancer.id)' 
        | project id,natPools = properties.inboundNatPools
        | mv-expand natPool = natPools
        | extend natPoolId = tostring(natPool.id)
        | project natPoolId,loadBalancerId=id
        | join ( 
            resources
            | where type == 'microsoft.compute/virtualmachinescalesets'
            | project id,nicConfigs = properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations
            | where nicConfigs has '$($LoadBalancer.id)'
            | mv-expand nicConfig = nicConfigs
            | mv-expand ipConfig = nicConfig.properties.ipConfigurations
            | extend constructedIpConfigId = strcat(id,'/_nicConfigs/_',nicConfig.name,'/_ipConfig/_',ipConfig.name)
            | mv-expand associatedNatPool = ipConfig.properties.loadBalancerInboundNatPools
            | extend natPoolId = tostring(associatedNatPool.id)
            | project vmssId=id,natPoolId,constructedIpConfigId
            ) on natPoolId
        | project-away natPoolId1
        | summarize natPoolVMSSMembers = make_set(constructedIpConfigId) by natPoolId,loadBalancerId,vmssId
"@

    $natPoolIpConfigs = Search-ResourceGraph -graphQuery $natPoolIpConfigQuery

    If ($backendPoolReuseStrategy -eq 'NoReuse') {
        Write-Verbose "Skipping backend pool reuse check. Backend pools will not be reused (unless manual mapping specifies)."

        ForEach ($natPoolIpConfig in $natPoolIpConfigs) {
            if (!$natPoolToBEPMap[$natPoolIpConfig.natPoolId]) {
                $natPoolToBEPMap[$natPoolIpConfig.natPoolId] = $null
            }
        }

        return $natPoolToBEPMap
    }

    # check for backend pools with the same membership as each nat pool
    ForEach ($natPoolIpConfig in $natPoolIpConfigs) {
        Write-Verbose "Checking NAT Pool '$($natPoolIpConfig.natPoolId.split('/')[-1])' for matching backend pools..."

        If ($natPoolToBEPMap[$natPoolIpConfig.natPoolId]) {
            Write-Verbose "Backend Pool already mapped for NAT Pool '$($natPoolIpConfig.natPoolId.split('/')[-1])' using manual config. Skipping comparison."
            continue
        }

        ForEach ($backendPoolIpConfig in $backendPoolIpConfigs) {
            If ($backendPoolIpConfig.backendPoolMembers.count -eq $natPoolIpConfig.natPoolVMSSMembers.count) {
                $natMembersNotInBackendPool = [string[]][Linq.Enumerable]::Except([string[]]$natPoolIpConfig.natPoolVMSSMembers, [string[]]$backendPoolIpConfig.backendPoolMembers)

                Write-Verbose "natMembersNotInBackendPool: $($natMembersNotInBackendPool -join ',')"
            }
            Else {
                Write-Verbose "'$($backendPoolIpConfig.backendPoolId.split('/')[-1])' has a different number of members. Skipping comparison."
                continue
            }

            If ($natMembersNotInBackendPool.count -eq 0) {
                If (-NOT [string]::IsNullOrEmpty($natPoolToBEPMap[$natPoolIpConfig.natPoolId])) {
                    Write-Warning "Multiple backend pools have the same membership as NAT Pool '$($natPoolIpConfig.natPoolId.split('/')[-1])'. Backend pool '$($backendPoolIpConfig.backendPoolId.split('/')[-1])' will be used for this NAT pool."
                }

                Write-Verbose "Backend pool '$($backendPoolIpConfig.backendPoolId.split('/')[-1])' has the same membership as NAT Pool '$($natPoolIpConfig.natPoolId.split('/')[-1])'. Reusing backend pool."
                $natPoolToBEPMap[$natPoolIpConfig.natPoolId] = $backendPoolIpConfig.backendPoolId
            }
            Else {
                Write-Verbose "Backend Pool '$($backendPoolIpConfig.backendPoolId.split('/')[-1])' does not have the same membership as NAT Pool '$($natPoolIpConfig.natPoolId.split('/')[-1])'. Different members: $comparison. Skipping."
                continue
            }
        }
    }

    Write-Verbose "natPoolToBEPMap: $($natPoolToBEPMap | ConvertTo-Json -Depth 3)"

    return $natPoolToBEPMap

}
    Function Search-ResourceGraph {
        param (
            [Parameter(Mandatory = $True)][string] $graphQuery
        )

        Write-Verbose "Graph Query Text: `n$graphQuery"

        # query the resource graph, implementing pagination to ensure all records are returned
        $queryResult = ''
        $queryResults = @()
        do {      
            $optionalParams = @{}
            If ($queryResult.SkipToken) {
                $optionalParams['skipToken'] = $queryResult.SkipToken
            }
    
            $queryResult = Search-AzGraph -Query $graphQuery @optionalParams
            $queryResults += $queryResult.Data
        } while ($queryResult.SkipToken)

        return $queryResults
    }

    $ErrorActionPreference = 'Stop'

    Write-Host "Starting NAT Pool Migration..."

    # get load balancer if not passed through pipeline
    try {
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $LoadBalancer = Get-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $LoadBalancerName
        }
    }
    catch {
        Write-Error "Failed to find Load Balancer '$LoadBalancerName' in Resource Group '$ResourceGroupName'. Ensure that the name values are correct and that you have appropriate permissions."
    }

    Write-Host "Validating and preparing Load Balancer '$($LoadBalancer.Name)' for NAT Pool Migration..."

    # check load balancer sku
    If ($LoadBalancer.sku.name -ne 'Standard') {
        Write-Error "In order to migrate to NAT Rules, the Load Balancer must be a Standard SKU. Upgrade the Load Balancer first. See: https://learn.microsoft.com/azure/load-balancer/load-balancer-basic-upgrade-guidance"
    }

    # check load balancer has inbound nat pools
    If ($LoadBalancer.InboundNatPools.count -lt 1) {
        Write-Error "Load Balancer '$($loadBalancer.Name)' does not have any Inbound NAT Pools to migrate"
    }

    # check whether existing backend pools membership aligns to nat pools if -reuseBackendPools specified
    ##  nat pool to backend pool mapping dictionary - this is used later in the script to reuse backend pools for nat rules
    $natPoolToBEPMap = @{} + $manualBackendPoolMap # { natPoolId = backendPoolId; ... }
    $natPoolToBEPMap = Get-NATToBackendPoolMap -LoadBalancer $LoadBalancer -natPoolToBEPMap $natPoolToBEPMap -backendPoolReuseStrategy $backendPoolReuseStrategy

    Write-Host "NAT Pool to Backend Pool mapping/alignment:"
    $natPoolToBEPMap.GetEnumerator() | ForEach-Object {
        $natPoolName = $_.Key.split('/')[-1]
        If ($null -eq $_.Value) {
            $bePoolName = "NEW: {0}{1}" -f 'be_migrated_',$_.Key.split('/')[-1]
        }
        Else {
            $bePoolName = $_.Value.split('/')[-1]
        }
        Write-Host "`tNAT Pool: '$natPoolName' -> Backend Pool: '$bePoolName'"
    }

    switch ($backendPoolReuseStrategy) {
        'FirstMatch' {
            Write-Host "Using 'FirstMatch' (the default) backend pool reuse strategy. The first matching backend pool will be used for each NAT Pool."

            $missingMatch = $false
            ForEach ($natPool in $natPoolToBEPMap.GetEnumerator()) {
                If ([string]::IsNullOrEmpty($natPool.Value)) {
                    $missingMatch = $true
                    Write-Error "No matching backend pool found for NAT Pool '$($natPool.Key.split('/')[-1])'. Either create a new backend pool with the same membership as the NAT Pool or switch to -backendPoolReuseStrategy 'OptionalFirstMatch' or 'NoReuse'." -ErrorAction Continue
                }
            }

            If ($missingMatch) {
                return
            }
        }
        'OptionalFirstMatch' {
            Write-Host "Using 'OptionalFirstMatch' backend pool reuse strategy. The first matching backend pool will be used for each NAT Pool. If no matching backend pool is found, a new backend pool will be created."
        }
        'NoReuse' {
            Write-Host "Using 'NoReuse' backend pool reuse strategy. A new backend pool will be created for each NAT Pool."
        }
    }

    If ($validateOnly) {
        Write-Host "Validation complete. Exiting due to -validateOnly paramater."
        return
    }

    Write-Host "Validation complete, starting NAT Pool Migration..."

    # create a hard copy of NAT Pool configs for later reference
    $inboundNatPoolConfigs = $LoadBalancer.InboundNatPools | ConvertTo-Json | ConvertFrom-Json

    # get add virtual machine scale sets associated with the LB NAT Pools (via NAT Pool-create NAT Rules)
    If (!$LoadBalancer.InboundNatRules) {
        Write-Error "Load Balancer '$($loadBalancer.Name)' does not have any Inbound NAT Rules. This is unexpected. NAT Rules are created automatically when the VMSS Network Profile is updated to include an Inbound NAT Pool and the VMSS instances are updated with the VMSS model. If you just added a VMSS to your NAT Pool, update your VMSS instances and try again."
    }

    ## use a resource graph query to get the scale sets associated with the load balancer's backend pools and nat pools
    $natPoolsPrefix = $LoadBalancer.id + '/inboundNatPools/'
    $graphQuery = @"
        resources 
        | where type == 'microsoft.compute/virtualmachinescalesets'
        | project id,nicConfigs = properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations
        | where nicConfigs has '$natPoolsPrefix'
        | project id
"@

    $vmssIds = Search-ResourceGraph -graphQuery $graphQuery | Select-Object -ExpandProperty id | Sort-Object -Unique

    Write-Verbose "Found '$($vmssIds.count)' unique VMSSes associated with the Load Balancer's NAT Pools."

    If ([string]::IsNullOrEmpty($vmssIds)) {
        Write-Host "Load Balancer '$($loadBalancer.Name)' does not have any VMSSes associated with its NAT Pools."
    }
    Else {
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
    }

    Write-Host "Starting Load Balancer NAT Pool migration..."

    If (![string]::IsNullOrEmpty($vmssIds)) {
        # remove each vmss model's ipconfig from the load balancer's inbound nat pool
        Write-Host "Removing the NAT Pool from the VMSS model ipConfigs."
        $ipConfigNatPoolMap = @()
        ForEach ($inboundNATPool in $LoadBalancer.InboundNatPools) {
            ForEach ($vmssItem in $vmsses) {
                ForEach ($nicConfig in $vmssItem.vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
                    ForEach ($ipConfig in $nicConfig.ipConfigurations) {
                        If ($ipConfig.loadBalancerInboundNatPools.id -contains $inboundNATPool.id) {

                            Write-Host "Removing NAT Pool '$($inboundNATPool.id.split('/')[-1])' from VMSS '$($vmssItem.vmss.Name)' NIC '$($nicConfig.Name)' ipConfig '$($ipConfig.Name)'"
                            $ipConfigParams = @{vmssId = $vmssItem.vmss.id; nicName = $nicConfig.Name; ipconfigName = $ipConfig.Name; inboundNatPoolId = $inboundNatPool.id }
                            $ipConfigNatPoolMap += $ipConfigParams

                            # remove the nat pool from the ip config loadBalancerInboundNatPools list
                            $ipConfig.loadBalancerInboundNatPools.Remove(($ipConfig.loadBalancerInboundNatPools | Where-Object { $_.id -eq $inboundNATPool.Id })) | Out-Null

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

        Write-Host "Start waiting for VMSS model to update to remove the NAT Pool references..."
        While ($vmssModelUpdateRemoveNATPoolJobs.State -contains 'Running') {
            Start-Sleep -Seconds 15
            Write-Host "`tWaiting for VMSS model update jobs to complete..."
        } 
        
        $vmssModelUpdateRemoveNATPoolJobs | Foreach-Object {
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
    }

    # remove all NAT pools to avoid port conflicts with NAT rules
    $LoadBalancer.InboundNatPools = $null

    # update the load balancer config
    $LoadBalancer = $LoadBalancer | Set-AzLoadBalancer 

    # update load balancer with nat rule configurations
    ForEach ($inboundNATPool in $inboundNatPoolConfigs) {

        If (!$natPoolToBEPMap[$inboundNATPool.Id]) {
            Write-Host "Creating new Backend Pool for NAT Pool '$($inboundNATPool.Name)'"
            # add a new backend pool for the NAT rule
            $backendPoolName = "be_migrated_$($inboundNATPool.Name)"

            Write-Host "Adding new Backend Pool '$backendPoolName' to LB for NAT Pool '$($inboundNATPool.Name)'"
            $LoadBalancer = $LoadBalancer | Add-AzLoadBalancerBackendAddressPoolConfig -Name $backendPoolName
            $natPoolToBEPMap[$inboundNATPool.Id] = '{0}/backendAddressPools/{1}' -f $LoadBalancer.Id, $backendPoolName

            # update the load balancer config
            $LoadBalancer = $LoadBalancer | Set-AzLoadBalancer
        }
        Else {
            $backendPoolName = $($natPoolToBEPMap[$inboundNATPool.Id].split('/')[-1])
            Write-Host "Reusing existing Backend Pool '$backendPoolName' for NAT Pool '$($inboundNATPool.Name)'"
        } 

        # add a NAT rule config
        $frontendIPConfiguration = New-Object Microsoft.Azure.Commands.Network.Models.PSFrontendIPConfiguration
        $frontendIPConfiguration.id = $inboundNATPool.FrontendIPConfiguration.Id

        $backendAddressPool = $LoadBalancer.BackendAddressPools | Where-Object { $_.name -eq $backendPoolName }

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

    If (![string]::IsNullOrEmpty($vmssIds)) {
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

                        # add this IP config to each backend pool associated with new NAT Rules
                        ForEach ($backendPoolId in $natPoolToBEPMap[$ipconfigRecord.inboundNatPoolId]) {
                            #$backendPoolObj = new-object Microsoft.Azure.Commands.Network.Models.PSBackendAddressPool
                            $backendPoolObj = New-Object Microsoft.Azure.Management.Compute.Models.SubResource
                            $backendPoolObj.id = $backendPoolId

                            Write-Host "Adding VMSS '$($vmssItem.vmss.Name)' NIC '$($nicConfig.Name)' ipConfig '$($ipConfig.Name)' to backend pool '$($backendPoolObj.id.split('/')[-1])'"
                            $backendPoolList.Add($backendPoolObj)
                        }

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

        Write-Host "Start waiting for VMSS model to update to include the new Backend Pools..."
        While ($vmssModelUpdateAddBackendPoolJobs.State -contains 'Running') {
            Start-Sleep -Seconds 15
            Write-Host "`tWaiting for VMSS model update jobs to complete..."
        } 
    
        $vmssModelUpdateAddBackendPoolJobs | Foreach-Object {
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

    Write-Host "NAT Pool Migration complete."
}

Export-ModuleMember -Function Start-AzNATPoolMigration 