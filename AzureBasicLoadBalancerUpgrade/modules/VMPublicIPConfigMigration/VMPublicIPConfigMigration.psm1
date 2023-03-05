Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")

Function UpgradeVMPublicIP {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer
    )

    log -Message "[UpgradeVMPublicIP] Starting upgrade of Public IP SKUs for VMs associated with the Basic Load Balancer $($BasicLoadBalancer.Name)"

    # get the NIC IDs associated with the Basic Load Balancer
    $nicIDs = @() 
    foreach ($backendAddressPool in $BasicLoadBalancer.BackendAddressPools) {
        foreach ($backendIpConfiguration in ($backendAddressPool.BackendIpConfigurations | Select-Object -Unique)) {
            $nicIDs += "'$(($backendIpConfiguration.Id -split '/ipconfigurations/')[0])'"
        }
    }

    $joinedNicIDs = $nicIDs -join ','
    
    # get VMs associated with the Lb NIC IDs which have Public IP Addresses, return public IP IDs
    # every PIP assiciated with a VM must be the same SKU, and align with the SKU of the load balancer
    #
    # NOTE: the resoruce graph data will lag behind ARM by a couple minutes, so creating resource and immediately 
    #   attempting migration (as in a test) will result in not ARG results. As a workaround, set the Environment Variable $env:LBMIG_WAIT_FOR_ARG = $true
    #

    $graphQuery = @"
    Resources |
        where type =~ 'microsoft.network/networkinterfaces' and id in~ ($joinedNicIDs) | 
        project lbNicVMId = tostring(properties.virtualMachine.id) |
        join ( Resources | where type =~ 'microsoft.compute/virtualmachines' | project vmId = id, vmNics = properties.networkProfile.networkInterfaces) on `$left.lbNicVMId == `$right.vmId |
        join ( Resources | where type =~ 'microsoft.network/networkinterfaces' | project nicVMId = tostring(properties.virtualMachine.id), allVMNicID = id, nicIPConfigs = properties.ipConfigurations ) on `$left.vmId == `$right.nicVMId |
        join ( Resources | where sku.name == 'Basic' |
            where type =~ 'microsoft.network/publicipaddresses' and isnotnull(properties.ipConfiguration.id) | 
            project pipId = id, pipAssociatedNicId = tostring(split(properties.ipConfiguration.id,'/ipConfigurations/')[0]),pipIpConfig = properties.ipConfiguration.id) on `$left.allVMNicID == `$right.pipAssociatedNicId |
    project pipId,vmNics,nicIPConfigs,pipIpConfig,pipAssociatedNicId
"@

    log -Severity Verbose -Message "Graph Query Text: `n$graphQuery"

    $waitingForARG = $false
    $timeoutStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    do {        
        If (!$waitingForARG) {
            log -Message "[UpgradeVMPublicIP] Querying Resource Graph for PIPs to upgrade..."
        }
        Else {
            log -Message "[UpgradeVMPublicIP] Waiting 15 seconds before querying ARG again..."
            Start-Sleep 15
        }

        $publicIPsToUpgrade = Search-AzGraph -Query $graphQuery

        $waitingForARG = $true
    } while ($publicIPsToUpgrade.count -eq 0 -and $env:LBMIG_WAIT_FOR_ARG -and $timeoutStopwatch.Elapsed.Minutes -lt 15)

    log -Message "[UpgradeVMPublicIP] Found '$($publicIPsToUpgrade.count)' Public IPs associcated with VMs in the Basic LB's backend pool to upgrade"

    $pipAllocationMethodJobs = @()
    ForEach ($pipRecord in $publicIPsToUpgrade) {
        $pipRecord | Add-Member @{pipObject = ($pip = Get-AzResource -ResourceId $pipRecord.pipId | Get-AzPublicIpAddress)}

        If ($pipRecord.pipObject.PublicIpAllocationMethod -eq 'Dynamic') {
            log -Message "[UpgradeVMPublicIP] Public IP '$($pipRecord.pipObject.id)' allocation is Dynamic, changing to Static to support upgrade to Standard SKU"
            $pipRecord.pipObject.PublicIpAllocationMethod = 'Static'

            $pipAllocationMethodJobs += $pipRecord.pipObject | Set-AzPublicIpAddress -AsJob
        }
        Else {
            log -Message "[UpgradeVMPublicIP] Public IP '$($pipRecord.pipObject.id)' allocation is Static, no change required"
        }
    }

    log -Message "[UpgradeVMPublicIP] Waiting for '$($pipAllocationMethodJobs.count)' PIP allocation method change jobs to complete before starting upgrade of Public IP SKUs"
    $pipAllocationMethodJobs | Wait-Job | Foreach-Object {
        $job = $_
        If ($job.Error -or $job.State -eq 'Failed') {
            $publicIPsToUpgrade | Select-Object -Property pipId,pipIpConfig | ConvertTo-Json
            log -Severity Error -Message "Changing a Public IP allocation method from Dynamic to Static failed with the following errors: $($job.error; $job | Receive-Job). To continue, address the error then follow the script documentation on recovering from a failed migration and try again." -terminateOnError
        }
    }

    # detach all PIPs from each VM in the backend pool (even from NICs not associated with the LB because all PIPs and LBs assoicated with a VM must be the same SKU)
    $nicDetachJobs = @()
    $nicsWithPIPsToReattach = @{}
    $nicGroupedPIPRecords = $publicIPsToUpgrade | Group-Object -Property pipAssociatedNicId
    ForEach ($nicGroup in $nicGroupedPIPRecords) {
        $nic = Get-AzResource -ResourceId $nicGroup.Name | Get-AzNetworkInterface

        $nicUpdateRequired = $false
        ForEach ($pipRecord in $nicGroup.Group) {
            
            log -Message "[UpgradeVMPublicIP] Detaching Public IP $($pipRecord.pipObject.Name) from NIC $($pipRecord.nicName) to upgrade to Standard SKU"
            $nicUpdateRequired = $true

            If (!$nicsWithPIPsToReattach[$nic.Id]) {
                $nicsWithPIPsToReattach[$nic.Id] = @(@{ipConfigs = @{} })
            }
            If (!$nicsWithPIPsToReattach[$nic.Id].ipConfigs[$pipRecord.pipIpConfig]) {
                $nicsWithPIPsToReattach[$nic.Id].ipConfigs[$pipRecord.pipIpConfig] = $pipRecord.pipId
            }

            $pipNicIPConfig = $nic.IpConfigurations | Where-Object { $_.Id -eq $pipRecord.pipIpConfig }
            $pipNicIPConfig.PublicIpAddress = $null

        }

        If ($nicUpdateRequired) {
            log -Message "[UpgradeVMPublicIP] Updating NIC $($nic.Name) to detach Public IPs from NIC"
            $nicDetachJobs += $nic | Set-AzNetworkInterface -AsJob
        }
    }

    log -Message "[UpgradeVMPublicIP] Waiting for all '$($nicDetachJobs.count)' NIC detach jobs to complete before starting upgrade of Public IP SKUs"
    $nicDetachJobs | Wait-Job | Foreach-Object {
        $job = $_
        If ($job.Error -or $job.State -eq 'Failed') {
            $pipToIpConfigTable = $publicIPsToUpgrade | Select-Object -Property pipId,pipIpConfig | ConvertTo-Json
            log -Severity Error -Message "Detaching PIP from an IP config failed with the following errors: $($job.error; $job | Receive-Job). Migration will continue--to recover, manually upgrade Public IPs and associate NICs with their Public IP Addresses after the script completes. Use the following table to match PIPs with IPconfigs: `n$pipToIpConfigTable"
        }
    }

    # update the PIPs to Standard SKU
    $pipUpgradeSKUJobs = @()
    ForEach ($pip in $publicIPsToUpgrade.pipObject) {
        log -Message "[UpgradeVMPublicIP] Upgrading Public IP '$($pip.Name)' to Standard SKU"

        $pip.Sku.Name = 'Standard'
        $pipUpgradeSKUJobs += $pip | Set-AzPublicIpAddress -AsJob
    }

    log -Message "[UpgradeVMPublicIP] Waiting for all '$($pipUpgradeSKUJobs.count)' PIP SKU upgrade jobs to complete"
    $nicDetachJobs | Wait-Job | Foreach-Object {
        $job = $_
        If ($job.Error -or $job.State -eq 'Failed') {
            $pipToIpConfigTable = $publicIPsToUpgrade | Select-Object -Property pipId,pipIpConfig | ConvertTo-Json
            log -Severity Error -Message "Upgrading Public IP to Standard SKU failed with the following errors: $($job.error; $job | Receive-Job). Migration will continue--to recover, manually upgrade Public IPs and associate NICs with their Public IP Addresses after the script completes. Use the following table to match PIPs with IPconfigs: `n$pipToIpConfigTable"
        }
    }

    # reattach the PIPs to the NICs - one job per NIC
    $nicPIPReattachJobs = @()
    ForEach ($nicRecord in $nicsWithPIPsToReattach.GetEnumerator()) {
        $nic = Get-AzResource -ResourceId $nicRecord.Name | Get-AzNetworkInterface

        ForEach ($ipConfigRecord in $nicsWithPIPsToReattach[$nicRecord.Name].ipConfigs.GetEnumerator()) {
            $ipConfig = $nic.IpConfigurations | Where-Object { $_.Id -eq $ipConfigRecord.Name }

            log -Message "[UpgradeVMPublicIP] Reattaching Public IP '$($nicsWithPIPsToReattach[$nicRecord.Name].ipConfigs[$ipConfigRecord.Name])' to NIC IPConfig '$($ipConfigRecord.Name)'"
            $ipConfig[0].PublicIpAddress = @{ id = $nicsWithPIPsToReattach[$nicRecord.Name].ipConfigs[$ipConfigRecord.Name] }
        }

        $nicPIPReattachJobs += $nic | Set-AzNetworkInterface -AsJob
    }

    log -Message "[UpgradeVMPublicIP] Waiting for '$($nicPIPReattachJobs.count)' PIP reattach to NIC jobs to complete..."
    $nicPIPReattachJobs | Wait-Job | Foreach-Object {
        $job = $_
        If ($job.Error -or $job.State -eq 'Failed') {
            log -Severity Error -Message "Reassociating upgraded Public IPs with NICs failed with the following errors: $($job.error; $job | Receive-Job). Migration will continue--to recover, manually associate NICs with their Public IP Addresses after the script completes."
        }
    }

    log -Message "[UpgradeVMPublicIP] Completed upgrade of VM Public IP SKUs"
}

Export-ModuleMember -Function UpgradeVMPublicIP