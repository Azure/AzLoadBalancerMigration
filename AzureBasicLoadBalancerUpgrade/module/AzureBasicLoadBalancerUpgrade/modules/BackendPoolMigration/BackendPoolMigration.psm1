# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/UpdateVmss/UpdateVmss.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/UpdateVmssInstances/UpdateVmssInstances.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/GetVmssFromBasicLoadBalancer/GetVmssFromBasicLoadBalancer.psd1")

function _HardCopyObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][System.Collections.Generic.List[Microsoft.Azure.Management.Compute.Models.SubResource]] $listSubResource
    )
    $options = [System.Text.Json.JsonSerializerOptions]::new()
    $options.WriteIndented = $true
    $options.IgnoreReadOnlyProperties = $true
    $cgenericListSubResource = [System.Text.Json.JsonSerializer]::Serialize($listSubResource, "System.Collections.Generic.List[Microsoft.Azure.Management.Compute.Models.SubResource]", $options)
    $cgenericListSubResource = [System.Text.Json.JsonSerializer]::Deserialize($cgenericListSubResource, "System.Collections.Generic.List[Microsoft.Azure.Management.Compute.Models.SubResource]")
    # To preserve the original object type in the return we must use a , before the object to be returned
    return , [System.Collections.Generic.List[Microsoft.Azure.Management.Compute.Models.SubResource]]$cgenericListSubResource
}

function _MigrateHealthProbe{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $vmss,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $refVmss
    )

    log -Message "[_MigrateHealthProbe] Migrating Health Probes"
    try {
        $refHealthProbe = $refVmss.VirtualMachineProfile.NetworkProfile.HealthProbe
        if(![string]::IsNullOrEmpty($refHealthProbe)){
            $refProbeName = $refHealthProbe.Id.Split('/')[-1]
            log -Message "[_MigrateHealthProbe] Health Probes found in reference VMSS $($refProbeName)"
            $refProbeId = ($StdLoadBalancer.Probes | Where-Object{$_.Name -eq $refProbeName}).id
            $vmss.VirtualMachineProfile.NetworkProfile.HealthProbe = $refProbeId
        }
        else{
            log -Message "[_MigrateHealthProbe] Health Probes not found in reference VMSS $($refVmss.Name)"
        }
    }
    catch {
            $message = @"
            [_MigrateHealthProbe] An error occured migrating a health probe to the VMSS. To recover
            address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup
            State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
        log 'Error' $message -terminateOnError
    }
    log -Message "[_MigrateHealthProbe] Migrating Health Probes completed"
}

function _RestoreUpgradePolicyMode{
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $vmss,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $refVmss
    )

    log -Message "[_RestoreUpgradePolicyMode] Restoring VMSS Upgrade Policy Mode"
    if ($vmss.UpgradePolicy.Mode -ne $refVmss.UpgradePolicy.Mode) {
        log -Message "[_RestoreUpgradePolicyMode] Restoring VMSS Upgrade Policy Mode to $($refVmss.UpgradePolicy.Mode)"
        $vmss.UpgradePolicy.Mode = $refVmss.UpgradePolicy.Mode
    }
    else {
        log -Message "[_RestoreUpgradePolicyMode] VMSS Upgrade Policy Mode not changed"
    }

    log -Message "[_RestoreUpgradePolicyMode] Restoring VMSS Upgrade Policy Mode completed"
}

function _MigrateNetworkInterfaceConfigurationsVmss {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $vmss
    )

    log -Message "[_MigrateNetworkInterfaceConfigurationsVmss] Adding BackendAddressPool to VMSS $($vmss.Name)"
    foreach ($networkInterfaceConfiguration in $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
        $genericListSubResource = New-Object System.Collections.Generic.List[Microsoft.Azure.Management.Compute.Models.SubResource]
        foreach ($ipConfiguration in $networkInterfaceConfiguration.IpConfigurations) {
            If (![string]::IsNullOrEmpty($ipConfiguration.LoadBalancerBackendAddressPools)) {
                $genericListSubResource.AddRange($ipConfiguration.LoadBalancerBackendAddressPools)
            }

            foreach($BackendAddressPool in $BasicLoadBalancer.BackendAddressPools){
                foreach($BackendIpConfiguration in $BackendAddressPool.BackendIpConfigurations){
                    $lbBeNicName = $BackendIpConfiguration.Id.Split('/')[-3]
                    $lbBeipConfigName = $BackendIpConfiguration.Id.Split('/')[-1]
                    if($lbBeNicName -eq $networkInterfaceConfiguration.Name -and $lbBeipConfigName -eq $ipConfiguration.Name){
                        try {
                            $subResource = New-Object Microsoft.Azure.Management.Compute.Models.SubResource
                            $subResource.Id = ($StdLoadBalancer.BackendAddressPools | Where-Object { $_.Name -eq $BackendAddressPool.Name }).Id
                            log -Message "[_MigrateNetworkInterfaceConfigurationsVmss] Adding BackendAddressPool $($subResource.Id.Split('/')[-1]) to VMSS Nic: $lbBeNicName ipConfig: $lbBeipConfigName"
                            $genericListSubResource.Add($subResource)
                        }
                        catch {
                            $message = @"
                                [_MigrateNetworkInterfaceConfigurationsVmss] An error occured creating a new VMSS IP Config. To recover
                                address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup
                                State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
                            log 'Error' $message -terminateOnError
                        }
                    }
                }
            }
            # Taking a hard copy of the object and assigning, it's important because the object was passed by reference
            $ipConfiguration.LoadBalancerBackendAddressPools = _HardCopyObject -listSubResource $genericListSubResource
            $genericListSubResource.Clear()
        }
    }
    log -Message "[_MigrateNetworkInterfaceConfigurationsVmss] Migrate NetworkInterface Configurations completed"
}

function BackendPoolMigrationVmss {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $refVmss
    )
    log -Message "[BackendPoolMigrationVmss] Initiating Backend Pool Migration"

    log -Message "[BackendPoolMigrationVmss] Adding Standard Load Balancer back to the VMSS"
    log -Message "[BackendPoolMigrationVmss] Building VMSS object from Basic Load Balancer $($BasicLoadBalancer.Name)"
    $vmss = GetVmssFromBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer

    # Migrating Health Probe in case it exist
    _MigrateHealthProbe -StdLoadBalancer $StdLoadBalancer -vmss $vmss -refVmss $refVmss

    # Migrating Network Interface Configurations back to the VMSS
    _MigrateNetworkInterfaceConfigurationsVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -vmss $vmss

    # Update VMSS on Azure
    try {
        Update-Vmss -vmss $vmss
    }
    catch {
        $message = "[BackendPoolMigrationVmss] An error occured while updating the VMSS to associate it with the standard load balancer's backend pool. To recover address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup State file located either in this directory or the directory specified with -RecoveryBackupPath. To manually complete the migration, add the VMSS to the appropriate backend pools and check that the VMSS Upgrade Policy mode is correct. `nError message: $_"

        log 'Error' $message -terminateOnError
    }

    # Update Instances
    UpdateVmssInstances -vmss $vmss

    # Restore VMSS Upgrade Policy Mode
    _RestoreUpgradePolicyMode -vmss $vmss -refVmss $refVmss

    # Update VMSS on Azure
    try {
        Update-Vmss -vmss $vmss
    }
    catch {
        $message = "[BackendPoolMigrationVmss] An error occured while restoring the VMSS Upgrade Policy Mode. To recover address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup State file located either in this directory or the directory specified with -RecoveryBackupPath. To manually complete the migration, the VMSS Upgrade Policy mode matches the mode in the VMSS state file export. `nError message: $_"

        log 'Error' $message -terminateOnError
    }

    #log -Message "[BackendPoolMigrationVmss] Updating VMSS Instances $($vmss.Name)"
    #UpdateVmssInstances -vmss $vmss

    #log -Message "[BackendPoolMigrationVmss] StackTrace $($StackTrace)" -Severity "Debug"
    log -Message "[BackendPoolMigrationVmss] Backend Pool Migration Completed"
}

function BackendPoolMigrationVM {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[BackendPoolMigrationVM] Initiating Backend Pool Migration"

    log -Message "[BackendPoolMigrationVM] Adding original VMs to the new Standard Load Balancer backend pools"

    # build table of NICs and their ipconfigs and associate them to backend pools
    $backendPoolNicTable = @{}
    ForEach ($BackendAddressPool in $BasicLoadBalancer.BackendAddressPools) {
        $backendPoolList = New-Object System.Collections.Generic.List[Microsoft.Azure.Commands.Network.Models.PSBackendAddressPool]

        ForEach ($BackendIpConfiguration in $BackendAddressPool.BackendIpConfigurations) {
            $lbBeNicId = ($BackendIpConfiguration.Id -split '/ipConfigurations/')[0]
            $ipConfigName = ($BackendIpConfiguration.Id -split '/ipConfigurations/')[1]

            If (!$backendPoolNicTable[$lbBeNicId]) {
                $backendPoolNicTable[$lbBeNicId] = @(@{ipConfigs = @{} })
            }
            If (!$backendPoolNicTable[$lbBeNicId].ipConfigs[$ipConfigName]) {
                $backendPoolNicTable[$lbBeNicId].ipConfigs[$ipConfigName] = @{backendPools = $backendPoolList }
            }

            $backendPoolObj = new-object Microsoft.Azure.Commands.Network.Models.PSBackendAddressPool 
            $backendPoolObj.id = $StdLoadBalancer.BackendAddressPools | Where-Object { $_.Name -eq $BackendAddressPool.Name } | Select-Object -ExpandProperty Id
            $backendPoolNicTable[$lbBeNicId].ipConfigs[$ipConfigName].backendPools.add($backendPoolObj)
        }
    }

    # loop though nics and associate ipconfigs to backend pools
    $jobs = @()
    ForEach ($nicRecord in $backendPoolNicTable.GetEnumerator()) {

        log -Message "[BackendPoolMigrationVM] Adding ipconfigs on NIC $($nicRecord.Name.split('/')[-1]) to backend pools"

        try {
            $nic = Get-AzNetworkInterface -ResourceId $nicRecord.Name
        }
        catch {
            $message = @"
                [BackendPoolMigrationVmss] An error occured getting the Network Interface '$($nicRecord.Name)'. Check that the NIC exists. To recover
                address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup
                State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
            log 'Error' $message -terminateOnError
        }

        $nic = Get-AzNetworkInterface -ResourceId $nicRecord.Name

        ForEach ($nicIPConfig in $nic.IpConfigurations) {
            $nicIPConfig.LoadBalancerBackendAddressPools = $backendPoolNicTable[$nicRecord.Name].ipConfigs[$nicIPConfig.Name].backendPools
        }

        $jobs += Set-AzNetworkInterface -NetworkInterface $nic -AsJob
    }

    log -Message "[BackendPoolMigrationVM] Waiting for all '$($jobs.count)' NIC backend pool association jobs to complete"
    $jobs | Wait-Job -Timeout $defaultJobWaitTimeout | Foreach-Object {
        $job = $_
        If ($job.Error -or $job.State -eq 'Failed') {
            log -Severity Error -Message "Associating NIC with LB Backend Pool failed with the following errors: $($job.error; $job | Receive-Job). Migration will continue--to recover, manually associate NICs with the backend pool after the script completes. See association table: `n $($backendPoolNicTable | ConvertTo-Json -depth 10)"
        }
    }

    #log -Message "[BackendPoolMigrationVmss] StackTrace $($StackTrace)" -Severity "Debug"
    log -Message "[BackendPoolMigrationVmss] Backend Pool Migration Completed"
}

Export-ModuleMember -Function BackendPoolMigrationVmss
Export-ModuleMember -Function BackendPoolMigrationVM
