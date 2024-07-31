
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

.PARAMETER reuseBackendPools
    By specifying this parameter, the module will not create new backend pools for each NAT Pool if an existing backend pool contains all the same members as the NAT Pool. For cases where
    multiple NAT Pools exist and some have matching backend pools while others do not, you'll get some new backend pools and some reused backend pools. The same backend pool can be reused for multiple NAT Pools.

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
        [Parameter(Mandatory = $false)][switch] $reuseBackendPools # specify if existing matched backend pools should be reused
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

#     Function Get-NATToBackendPoolMap {
#         [CmdletBinding()]
#         param (
#             [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $LoadBalancer,
#             [Parameter(Mandatory = $True)][hashtable] $natPoolToBEPMap
#         )
        
#         $backendPoolsPrefix = $LoadBalancer.id + '/backendAddressPools/'
#         $natPoolsPrefix = $LoadBalancer.id + '/inboundNatPools/'

#         # use a resource graph query to get the scale sets associated with the load balancer's backend pools and nat pools
#         $graphQuery = @"
#             resources 
#             | where type == 'microsoft.compute/virtualmachinescalesets'
#             | project id,nicConfigs = properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations
#             | where nicConfigs has '$natPoolsPrefix' or nicConfigs has '$backendPoolsPrefix'
# "@

#         $vmssRecords = Search-ResourceGraph -Query $graphQuery 

#         Write-Verbose "Found '$($VMSSRecords.count)' unique VMSSes associated with the Load Balancer's Backend Pools and NAT Rules."

#         # check whether each inbound nat pool has a backend pool with all its same members
#         Foreach ($inboundNATPool in $LoadBalancer.InboundNatPools) {
#             Write-Verbose "Checking if NAT Pool '$($inboundNATPool.Name)' has aligned backend pool"

#             $natPoolVMSSes = $VMSSRecords | Where-Object { $_.nicConfigs.properties.ipConfigurations.properties.loadBalancerInboundNatPools.id -contains $inboundNATPool.id }
#             Write-Verbose "Found '$($natPoolVMSSes.count)' VMSSes associated with NAT Pool '$($inboundNATPool.Name)'"

#             # get a list of all IP configurations that belong to the NAT Pool
#             $natPoolIPConfigs = @()
#             ForEach ($natPoolVMSS in $natPoolVMSSes) {
#                 $vmssId = $natPoolVMSS.id

#                 ForEach ($nicConfig in $natPoolVMSS.nicConfigs) {
#                     $nicConfigName = $nicConfig.name
#                     ForEach ($ipConfig in ($nicConfig.properties.ipConfigurations | Where-Object { $_.properties.loadBalancerInboundNatPools.id -contains $inboundNATPool.id })) {
#                         # create an identifier for the VMSS ipconfig
#                         $ipConfigIdentifier = "{0}+{1}+{2}" -f $vmssId, $nicConfigName, $ipConfig.name

#                         $natPoolIPConfigs += $ipConfigIdentifier
#                     }
#                 }
#             }

#             Write-Verbose "Found '$($natPoolIPConfigs.count)' IP Configurations associated with NAT Pool '$($inboundNATPool.Name)'"

#             # check whether every IP config is a member of the same backend pool
#             $ipConfigNatAndBackendPools = @{}
#             Foreach ($ipConfigIdentifier in $natPoolIPConfigs) {
#                 # find the VMSS IP config record matching the nat pool ipconfig identifier
#                 Foreach ($VMSSRecord in ($VMSSRecords | Where-Object { $_.id -eq $ipConfigIdentifier.split('+')[0] })) {
#                     ForEach ($nicConfig in ($VMSSRecord.nicConfigs | Where-Object { $_.name -eq $ipConfigIdentifier.split('+')[1] })) {
#                         ForEach ($ipConfig in ($nicConfig.properties.ipConfigurations | Where-Object { $_.name -eq $ipConfigIdentifier.split('+')[2] })) {
#                             # add a record for the VMSS ip config with the associated backend pool ids to the dictionary
#                             $ipConfigNatAndBackendPools[$ipConfigIdentifier] = $ipConfig.properties.loadBalancerBackendAddressPools.id
#                         }
#                     }
#                 }
#             }

#             # create a list of all backend pools associated with the VMSS IP Configurations which are also associated with the NAT Pool
#             $backendPoolIds = @()
#             $backendPoolIds += $ipConfigNatAndBackendPools.GetEnumerator() | Select-Object -Unique -Property Value | ForEach-Object { 
#                 if ($null -ne $_.Value) {$_.Value} }
#             Write-Verbose "Found '$($backendPoolIds.count)' unique Backend Pools associated with IP configs also associated with NAT Pool '$($inboundNATPool.Name)'"

#             ForEach ($backendPoolId in $backendPoolIds) {
#                 Write-Verbose "Checking if Backend Pool '$($backendPoolId.split('/')[-1])' has aligned backend pools by IP Configurations"

#                 If ($ipConfigNatAndBackendPools.GetEnumerator().Where({ $_.Value -notcontains $backendPoolId })) {
#                     Write-Verbose "Candidate backend pool '$($backendPoolId.split('/')[-1])' is not a member of all NAT Pool IP Configurations for NAT Pool '$($inboundNATPool.Name)'"
#                 }
#                 Else {
#                     # associate the first backend pool that has all the same members as the NAT Pool with the nat pool id
#                     Write-Host "Candidate backend pool '$($backendPoolId.split('/')[-1])' contains all of NAT Pool IP Configurations for NAT Pool '$($inboundNATPool.Name)'; confirming it does not have additional members..."
                    
#                     $natPoolToBEPMap[$inboundNATPool.id] = $backendPoolId

#                     Write-Verbose "Skipping checking additional backend pools for NAT Pool '$($inboundNATPool.Name)'"
#                     continue
#                 }
#             }            
#         }

#         return $natPoolToBEPMap
#     }

Function Get-NATToBackendPoolMap {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $LoadBalancer,
        [Parameter(Mandatory = $True)][hashtable] $natPoolToBEPMap
    )
    
    $backendPoolsPrefix = $LoadBalancer.id + '/backendAddressPools/'
    $natPoolsPrefix = $LoadBalancer.id + '/inboundNatPools/'

    $graphQuery = @"
        resources 
        | where type == 'microsoft.compute/virtualmachinescalesets'
        | project id,nicConfigs = properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations
        | where nicConfigs has '$natPoolsPrefix' or nicConfigs has '$backendPoolsPrefix'
"@

    $vmssRecords = Search-ResourceGraph -Query $graphQuery 

    Write-Verbose "Found '$($vmssRecords.count)' unique VMSSes associated with the Load Balancer's Backend Pools and NAT Rules."

    foreach ($inboundNATPool in $LoadBalancer.InboundNatPools) {
        Write-Verbose "Checking if NAT Pool '$($inboundNATPool.Name)' has aligned backend pool"

        $natPoolVMSSes = $vmssRecords | Where-Object { $_.nicConfigs.properties.ipConfigurations.properties.loadBalancerInboundNatPools.id -contains $inboundNATPool.id }
        Write-Verbose "Found '$($natPoolVMSSes.count)' VMSSes associated with NAT Pool '$($inboundNATPool.Name)'"

        $natPoolIPConfigs = @()
        foreach ($vmss in $natPoolVMSSes) {
            foreach ($nicConfig in $vmss.nicConfigs) {
                $ipConfigs = $nicConfig.properties.ipConfigurations | Where-Object { $_.properties.loadBalancerInboundNatPools.id -contains $inboundNATPool.id }
                $natPoolIPConfigs += $ipConfigs | ForEach-Object { "{0}+{1}+{2}" -f $vmss.id, $nicConfig.name, $_.name }
            }
        }

        Write-Verbose "Found '$($natPoolIPConfigs.count)' IP Configurations associated with NAT Pool '$($inboundNATPool.Name)'"

        $ipConfigNatAndBackendPools = @{}
        foreach ($ipConfigIdentifier in $natPoolIPConfigs) {
            $vmssId, $nicConfigName, $ipConfigName = $ipConfigIdentifier -split '\+'
            $vmssRecord = $vmssRecords | Where-Object { $_.id -eq $vmssId }
            $nicConfig = $vmssRecord.nicConfigs | Where-Object { $_.name -eq $nicConfigName }
            $ipConfig = $nicConfig.properties.ipConfigurations | Where-Object { $_.name -eq $ipConfigName }
            $ipConfigNatAndBackendPools[$ipConfigIdentifier] = $ipConfig.properties.loadBalancerBackendAddressPools.id
        }

        $backendPoolIds = $ipConfigNatAndBackendPools.Values | Select-Object -Unique
        Write-Verbose "Found '$($backendPoolIds.count)' unique Backend Pools associated with IP configs also associated with NAT Pool '$($inboundNATPool.Name)'"

        foreach ($backendPoolId in $backendPoolIds) {
            Write-Verbose "Checking if Backend Pool '$($backendPoolId.split('/')[-1])' has aligned backend pools by IP Configurations"

            if ($ipConfigNatAndBackendPools.Values -notcontains $backendPoolId) {
                Write-Verbose "Candidate backend pool '$($backendPoolId.split('/')[-1])' is not a member of all NAT Pool IP Configurations for NAT Pool '$($inboundNATPool.Name)'"
            } else {
                Write-Host "Candidate backend pool '$($backendPoolId.split('/')[-1])' contains all of NAT Pool IP Configurations for NAT Pool '$($inboundNATPool.Name)'; confirming it does not have additional members..."
                $natPoolToBEPMap[$inboundNATPool.id] = $backendPoolId
                Write-Verbose "Skipping checking additional backend pools for NAT Pool '$($inboundNATPool.Name)'"
                break
            }
        }
    }

    return $natPoolToBEPMap
}
    Function Search-ResourceGraph {
        param (
            [Parameter(Mandatory = $True)][string] $Query
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
    $natPoolToBEPMap = @{} # { natPoolId = backendPoolId, ... }
    If ($reuseBackendPools) {
        $natPoolToBEPMap = Get-NATToBackendPoolMap -LoadBalancer $LoadBalancer -natPoolToBEPMap $natPoolToBEPMap
    }
    Else {
        Write-Host "-reuseBackendPools not specified. New backend pools will be created for each NAT Pool."
    }

    # create a hard copy of NAT Pool configs for later reference
    $inboundNatPoolConfigs = $LoadBalancer.InboundNatPools | ConvertTo-Json | ConvertFrom-Json

    # get add virtual machine scale sets associated with the LB NAT Pools (via NAT Pool-create NAT Rules)
    If (!$LoadBalancer.InboundNatRules) {
        Write-Error "Load Balancer '$($loadBalancer.Name)' does not have any Inbound NAT Rules. This is unexpected. NAT Rules are created automatically when the VMSS Network Profile is updated to include an Inbound NAT Pool and the VMSS instances are updated with the VMSS mode."
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

    $vmssIds = Search-ResourceGraph -Query $graphQuery | Select-Object -ExpandProperty id | Sort-Object -Unique

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