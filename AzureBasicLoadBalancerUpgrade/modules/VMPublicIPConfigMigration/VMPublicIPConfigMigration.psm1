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
    $publicIPsToUpgrade = Search-AzGraph -Query @"
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
    $pipAllocationMethodJobs | Wait-Job

    # for VMs with more than one PIP, detach all but the primary PIP, upgrade, and reattach
    $nicDetachJobs = @()
    $nicGroupedPIPRecords = $publicIPsToUpgrade | Group-Object -Property pipAssociatedNicId
    ForEach ($nicGroup in $nicGroupedPIPRecords) {
        $nic = Get-AzResource -ResourceId $nicGroup.Name | Get-AzNetworkInterface

        $nicUpdateRequired = $false
        ForEach ($pipRecord in $nicGroup.Group) {
            $primaryNic = $pipRecord.vmNics | Where-Object { $_.properties.primary -eq $true } | Select-Object -Expand Id
            $primaryIpConfig = $pipRecord.nicIPConfigs | Where-Object { $_.properties.primary -eq $true } | Select-Object -Expand Id
            
            If ($pipRecord.ipConfig -ne $primaryIpConfig -and $pipRecord.pipAssociatedNicId -ne $primaryNic) {
                log -Message "[UpgradeVMPublicIP] Detaching Public IP $($pipRecord.pipObject.Name) from NIC $($pipRecord.nicName) to upgrade to Standard SKU"
                $nicUpdateRequired = $true

                $pipNicIPConfig = $nic.IpConfigurations | Where-Object { $_.Id -eq $pipRecord.ipConfig }
                $pipNicIPConfig.PublicIpAddress = $null
            }
            Else {
                log -Message "[UpgradeVMPublicIP] Skipping detaching Public IP $($pipRecord.pipObject.Name) from NIC $($pipRecord.nicName) to upgrade to Standard SKU because it is on the primary NIC and IP Config"
            }
        }

        If ($nicUpdateRequired) {
            log -Message "[UpgradeVMPublicIP] Updating NIC $($nic.Name) to detach Public IPs from NIC"
            $nicDetachJobs += $nic | Set-AzNetworkInterface -AsJob
        }
    }

    log -Message "[UpgradeVMPublicIP] Waiting for all '$($nicDetachJobs.count)' NIC detach jobs to complete before starting upgrade of Public IP SKUs"
    $nicDetachJobs | Wait-Job

    # update the PIPs to Standard SKU
    $pipUpgradeSKUJobs = @()
    ForEach ($pip in $publicIPsToUpgrade.pipObject) {
        log -Message "[UpgradeVMPublicIP] Upgrading Public IP '$($pip.Name)' to Standard SKU"

        $pip.Sku.Name = 'Standard'
        $pipUpgradeSKUJobs += $pip | Set-AzPublicIpAddress -AsJob
    }

    log -Message "[UpgradeVMPublicIP] Waiting for all '$($pipUpgradeSKUJobs.count)' PIP SKU upgrade jobs to complete"
    $nicDetachJobs | Wait-Job

    # reattach the PIPs to the NICs
    ForEach ($nicGroup in $nicGroupedPIPRecords) {
        $nic = Get-AzResource -ResourceId $nicGroup.Name | Get-AzNetworkInterface

        $nicUpdateRequired = $false
        ForEach ($pipRecord in $nicGroup) {
            $primaryNic = $pipRecord.vmNics | Where-Object { $_.properties.primary -eq $true } | Select-Object -Expand Id
            $primaryIpConfig = $pipRecord.nicIPConfigs | Where-Object { $_.properties.primary -eq $true } | Select-Object -Expand Id
            
            If ($pipRecord.ipConfig -ne $primaryIpConfig -and $pipRecord.pipAssociatedNicId -ne $primaryNic) {
                log -Message "[UpgradeVMPublicIP] Reattaching Public IP '$($pipRecord.pipObject.Name)' to NIC $($pipRecord.nicName) to upgrade to Standard SKU"
                $nicUpdateRequired = $true

                $pipNicIPConfig = $nic.IpConfigurations | Where-Object { $_.Id -eq $pipRecord.ipConfig }
                $pipNicIPConfig.PublicIpAddress = $pipRecord.pipId
            }
        }

        If ($nicUpdateRequired) {
            log -Message "[UpgradeVMPublicIP] Updating NIC $($nic.Name) to detach Public IPs from NIC"
            $nicDetachJobs += $nic | Set-AzNetworkInterface -AsJob
        }
    }

    log -Message "[UpgradeVMPublicIP] Completed upgrade of VM Public IP SKUs"
}

Export-ModuleMember -Function UpgradeVMPublicIP