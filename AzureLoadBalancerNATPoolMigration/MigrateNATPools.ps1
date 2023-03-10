[CmdletBinding()]
param(
    [Parameter(Mandatory = $True, ParameterSetName = 'ByName')][string] $ResourceGroupName,
    [Parameter(Mandatory = $True, ParameterSetName = 'ByName')][string] $LoadBalancerName,
    [Parameter(Mandatory = $True, ValueFromPipeline, ParameterSetName = 'ByObject')][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $LoadBalancer
)

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

$inboundNatPoolConfigs = $LoadBalancer.InboundNatPools | ConvertTo-Json | ConvertFrom-Json
$vmssIds = $LoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object { ($_ -split '/virtualMachines/')[0].ToLower() } | Select-Object -Unique
$vmssObjects = $vmssIds | ForEach-Object { Get-AzResource -ResourceId $_ | Get-AzVmss }

# build vmss table
$vmsses = @()
ForEach ($vmss in $vmssObjects) {
    $vmsses += @{
        vmss = $vmss
        updateRequired = $false
    }
}

# check that vmsses use Manual or Automatic upgrade policy
$incompatibleUpgradePolicyVMSSes = $vmsses.vmss | Where-Object { $_.UpgradePolicy.Mode -notIn 'Manual','Automatic' }
If ($incompatibleUpgradePolicyVMSSes.count -gt 0) {
    Write-Error "The following VMSSes have upgrade policies which are not Manual or Automatic: $($incompatibleUpgradePolicyVMSSes.id)"
}

# remove each vmss model's ipconfig from the load balancer's inbound nat pool
Write-Verbose "Removing the NAT Pool from the VMSS model ipConfigs."
$ipConfigNatPoolMap = @()
ForEach ($inboundNATPool in $LoadBalancer.InboundNatPools) {
    ForEach ($vmssItem in $vmsses) {
        ForEach ($nicConfig in $vmssItem.vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
            ForEach ($ipConfig in $nicConfig.ipConfigurations) {
                If ($ipConfig.loadBalancerInboundNatPools.id -contains $inboundNATPool.id) {

                    Write-Verbose "Removing NAT Pool '$($inboundNATPool.id)' from VMSS '$($vmssItem.vmss.Name)' NIC '$($nicConfig.Name)' ipConfig '$($ipConfig.Name)'"
                    $ipConfigParams = @{vmssId=$vmssItem.vmss.id; nicName = $nicConfig.Name; ipconfigName = $ipConfig.Name; inboundNatPoolId = $inboundNatPool.id}
                    $ipConfigNatPoolMap += $ipConfigParams
                    $ipConfig.loadBalancerInboundNatPools = $ipConfig.loadBalancerInboundNatPools | Where-Object {$_.id -ne $inboundNATPool.Id}

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

Write-Verbose "Waiting for VMSS model to update to remove the NAT Pool references..."
$vmssModelUpdateRemoveNATPoolJobs | Wait-Job | Foreach-Object {
    $job = $_
    If ($job.Error -or $job.State -eq 'Failed') {
        Write-Error "An error occured while updating the VMSS model to remove the NAT Pools: $($job.error; $job | Receive-Job)."
    }
}

# update all vmss instances
$vmssInstanceUpdateRemoveNATPoolJobs = @()
ForEach ($vmssItem in ($vmsses | Where-Object { $_.updateRequired })) {
    $vmss = $vmssItem.vmss
    $vmssInstances = Get-AzVmssVM -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name

    $job = Update-AzVmssInstance -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name -InstanceId $vmssInstances.InstanceId -AsJob
    $job.Name = $vmss.vmss.Name + '_instanceUpdateRemoveNATPool'
    $vmssInstanceUpdateRemoveNATPoolJobs += $job
}

Write-Verbose "Waiting for VMSS instances to update to remove the NAT Pool references..."
$vmssInstanceUpdateRemoveNATPoolJobs | Wait-Job | Foreach-Object {
    $job = $_
    If ($job.Error -or $job.State -eq 'Failed') {
        Write-Error "An error occured while updating the VMSS instances to remove the NAT Pools: $($job.error; $job | Receive-Job)."
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

    Write-Verbose "Adding new Backend Pool '$newBackendPoolName' to LB for NAT Pool '$($inboundNATPool.Name)'"
    $LoadBalancer = $LoadBalancer | Add-AzLoadBalancerBackendAddressPoolConfig -Name $newBackendPoolName
    $natPoolToBEPMap[$inboundNATPool.Id] = '{0}/backendAddressPools/{1}' -f $LoadBalancer.Id,$newBackendPoolName

    # update the load balancer config
    $LoadBalancer = $LoadBalancer | Set-AzLoadBalancer 

    # add a NAT rule config
    $frontendIPConfiguration = New-Object Microsoft.Azure.Commands.Network.Models.PSFrontendIPConfiguration
    $frontendIPConfiguration.id = $inboundNATPool.FrontendIPConfiguration.Id

    $backendAddressPool = $LoadBalancer.BackendAddressPools | Where-Object { $_.name -eq $newBackendPoolName }

    $newNatRuleName = "natrule_migrated_$($inboundNATPool.Name)"

    Write-Verbose "Adding new NAT Rule '$newNatRuleName' to LB..."
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
Write-Verbose "Adding new backend pools to VMSS model ipConfigs..."

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

                Write-Verbose "Adding VMSS '$($vmssItem.vmss.Name)' NIC '$($nicConfig.Name)' ipConfig '$($ipConfig.Name)' to new backend pool '$($backendPoolObj.id)'"
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

Write-Verbose "Waiting for VMSS model to update to include the new Backend Pools..."
$vmssModelUpdateAddBackendPoolJobs | Wait-Job | Foreach-Object {
    $job = $_
    If ($job.Error -or $job.State -eq 'Failed') {
        Write-Error "An error occured while updating the VMSS model to add the NAT Rules: $($job.error; $job | Receive-Job)."
    }
}
 

# update all vmss instances to include the backend pool
Write-Verbose "Waiting for VMSS instances to update to include the new Backend Pools..."
$vmssInstanceUpdateAddBackendPoolJobs = @()
ForEach ($vmssItem in ($vmsses | Where-Object { $_.updateRequired })) {
    $vmss = $vmssItem.vmss
    $vmssInstances = Get-AzVmssVM -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name

    $job = Update-AzVmssInstance -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name -InstanceId $vmssInstances.InstanceId -AsJob
    $job.Name = $vmss.vmss.Name + '_instanceUpdateAddBackendPool'
    $vmssInstanceUpdateAddBackendPoolJobs += $job
}

$vmssInstanceUpdateAddBackendPoolJobs | Wait-Job | Foreach-Object {
    $job = $_
    If ($job.Error -or $job.State -eq 'Failed') {
        Write-Error "An error occured while updating the VMSS instanaces to add the NAT Rules: $($job.error; $job | Receive-Job)."
    }
}
