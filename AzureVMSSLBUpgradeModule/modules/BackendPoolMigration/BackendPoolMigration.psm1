# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\UpdateVmssInstances\UpdateVmssInstances.psd1")

function _AddLoadBalancerBackendAddressPool {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )

    foreach ($basicBackendAddressPool in $BasicLoadBalancer.BackendAddressPools) {
        log -Message "[_AddLoadBalancerBackendAddressPool] Adding BackendAddressPool $($basicBackendAddressPool.Name)"
        try {
            $ErrorActionPreference = 'Stop'
            $StdLoadBalancer | Add-AzLoadBalancerBackendAddressPoolConfig -Name $basicBackendAddressPool.Name > $null
        }
        catch {
            $message = @"
                [_AddLoadBalancerBackendAddressPool] An error occured when adding a backend pool to the new Standard LB '$($StdLoadBalancer.Name)'. To recover
                address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup
                State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
            log 'Error' $message
            Exit
        }
    }

    try {
        log -Message "[_AddLoadBalancerBackendAddressPool] Saving added BackendAddressPool to Standard Load Balancer $($StdLoadBalancer.Name)"
        $StdLoadBalancer | Set-AzLoadBalancer > $null
    }
    catch {
        $message = @"
        [_AddLoadBalancerBackendAddressPool] An error occured when saving the added backend pools to the new Standard LB '$($StdLoadBalancer.Name)'. To recover
        address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup
        State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
        log 'Error' $message
        Exit
    }
}

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

function BackendPoolMigration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[BackendPoolMigration] Initiating Backend Pool Migration"
    log -Message "[BackendPoolMigration] Looping all BackendAddressPools"
    _AddLoadBalancerBackendAddressPool -StdLoadBalancer $StdLoadBalancer -BasicLoadBalancer $BasicLoadBalancer

    log -Message "[BackendPoolMigration] Adding Standard Load Balancer back to the VMSS"
    $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object { $_.split("virtualMachines")[0] } | Select-Object -Unique
    foreach ($vmssId in $vmssIds) {
        $vmssName = $vmssId.split("/")[8]
        $vmssRg = $vmssId.Split('/')[4]

        try {
            $ErrorActionPreference = 'Stop'
            $vmss = Get-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName
        }
        catch {
            $message = @"
                [BackendPoolMigration] An error occured when calling 'Get-AzVmss -ResourceGroupName '$vmssRg' -VMScaleSetName '$vmssName'. To recover
                address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup
                State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
            log 'Error' $message
            Exit
        }

        log -Message "[BackendPoolMigration] Adding BackendAddressPool to VMSS $($vmss.Name)"
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
                                log -Message "[BackendPoolMigration] Adding BackendAddressPool $($subResource.Id.Split('/')[-1]) to VMSS Nic: $lbBeNicName ipConfig: $lbBeipConfigName"
                                $genericListSubResource.Add($subResource)
                            }
                            catch {
                                $message = @"
                                    [BackendPoolMigration] An error occured creating a new VMSS IP Config. To recover
                                    address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup
                                    State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
                                log 'Error' $message
                                Exit
                            }
                        }
                    }
                }
                # Taking a hard copy of the object and assigning, it's important because the object was passed by reference
                $ipConfiguration.LoadBalancerBackendAddressPools = _HardCopyObject -listSubResource $genericListSubResource
                $genericListSubResource.Clear()
            }
        }
        log -Message "[BackendPoolMigration] Saving VMSS $($vmss.Name)"
        try {
            $ErrorActionPreference = 'Stop'
            Update-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName -VirtualMachineScaleSet $vmss > $null
        }
        catch {
            $message = @"
                [BackendPoolMigration] An error occured when attempting to update VMSS network config new Standard
                LB backend pool membership. To recover address the following error, and try again specifying the
                -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup State file located either in
                this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
            log 'Error' $message
            Exit
        }
        log -Message "[BackendPoolMigration] Updating VMSS Instances $($vmss.Name)"
        UpdateVmssInstances -vmss $vmss
    }
    #log -Message "[BackendPoolMigration] StackTrace $($StackTrace)" -Severity "Debug"
    log -Message "[BackendPoolMigration] Backend Pool Migration Completed"
}
Export-ModuleMember -Function BackendPoolMigration