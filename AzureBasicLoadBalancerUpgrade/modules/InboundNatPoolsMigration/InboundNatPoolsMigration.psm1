# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\UpdateVmss\UpdateVmss.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\UpdateVmssInstances\UpdateVmssInstances.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\GetVMSSFromBasicLoadBalancer\GetVMSSFromBasicLoadBalancer.psd1")
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
function _MigrateNetworkInterfaceConfigurations {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $vmss,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $refVmss
    )

    log -Message "[_MigrateNetworkInterfaceConfigurations] Adding InboundNATPool to VMSS $($vmss.Name)"
    foreach ($networkInterfaceConfiguration in $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
        $genericListSubResource = New-Object System.Collections.Generic.List[Microsoft.Azure.Management.Compute.Models.SubResource]
        foreach ($ipConfiguration in $networkInterfaceConfiguration.IpConfigurations) {
            If (![string]::IsNullOrEmpty($ipConfiguration.loadBalancerInboundNatPools)) {
                $genericListSubResource.AddRange($ipConfiguration.loadBalancerInboundNatPools)
            }

            foreach($InboundNatPool in $BasicLoadBalancer.InboundNatPools) {

                try {
                    # get the ipconfig from the VMSS as it was prior to starting the upgrade--we'll use this to determine which NAT Pools to assiciate with which ipconfig
                    $coorespondingRefVmssIpconfig = $refVmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations | 
                        Where-Object {$_.Name -eq $networkInterfaceConfiguration.Name} | 
                        Select-Object -ExpandProperty IpConfigurations | 
                        Where-Object {$_.Name -eq $ipConfiguration.Name}
                    $coorespondingRefVmssIpconfigNatPoolNames = @()
                    $coorespondingRefVmssIpconfig.loadBalancerInboundNatPools.id | ForEach-Object {
                        $coorespondingRefVmssIpconfigNatPoolNames += $_.Split("/")[-1]
                    }

                    $message = "[_MigrateNetworkInterfaceConfigurations] Checking if VMSS '$($vmss.Name)' NIC '$($networkInterfaceConfiguration.Name)' IPConfig '$($ipConfiguration.Name)' should be associated with NAT Pool '$($InboundNatPool.Name)'"
                    log -Message $message
                    If ($InboundNatPool.Id.split('/')[-1] -in $coorespondingRefVmssIpconfigNatPoolNames) {
                        $message = "[_MigrateNetworkInterfaceConfigurations] Adding NAT Pool '$($InboundNatPool.Name)' to IPConfig '$($ipConfiguration.Name)'"
                        log -Message $message
    
                        $subResource = New-Object Microsoft.Azure.Management.Compute.Models.SubResource
                        $subResource.Id = ($StdLoadBalancer.InboundNatPools | Where-Object { $_.Name -eq $InboundNatPool.Name }).Id
                        $genericListSubResource.Add($subResource)
                    }
                }
                catch {
                    $message = @"
                        [_MigrateNetworkInterfaceConfigurations] An error occured creating a new VMSS IP Config. To recover
                        address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup
                        State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
                    log 'Error' $message -terminateOnError
                }
            }
            # Taking a hard copy of the object and assigning, it's important because the object was passed by reference
            $ipConfiguration.loadBalancerInboundNatPools = _HardCopyObject -listSubResource $genericListSubResource
            $genericListSubResource.Clear()
        }
    }
    log -Message "[_MigrateNetworkInterfaceConfigurations] Migrate NetworkInterface Configurations completed"
}
function InboundNatPoolsMigration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $refVmss
    )
    log -Message "[InboundNatPoolsMigration] Initiating Inbound NAT Pools Migration"

    $inboundNatPools = $BasicLoadBalancer.InboundNatPools
    foreach ($pool in $inboundNatPools) {
        log -Message "[InboundNatPoolsMigration] Adding Inbound NAT Pool $($pool.Name) to Standard Load Balancer"
        $frontEndIPConfig = Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $StdLoadBalancer -Name ($pool.FrontEndIPConfiguration.Id.split('/')[-1])
        $inboundNatPoolConfig = @{
            Name                    = $pool.Name
            BackendPort             = $pool.backendPort
            Protocol                = $pool.Protocol
            EnableFloatingIP        = $pool.EnableFloatingIP
            EnableTcpReset          = $pool.EnableTcpReset
            FrontendIPConfiguration = $frontEndIPConfig
            FrontendPortRangeStart  = $pool.FrontendPortRangeStart
            FrontendPortRangeEnd    = $pool.FrontendPortRangeEnd
            IdleTimeoutInMinutes    = $pool.IdleTimeoutInMinutes
        }

        try {
            $ErrorActionPreference = 'Stop'
            $StdLoadBalancer | Add-AzLoadBalancerInboundNatPoolConfig @inboundNatPoolConfig > $null 
        }
        catch {
            $message = "[InboundNatPoolsMigration] An error occured when adding Inbound NAT Pool config '$($pool.name)' to the new Standard 
                Load Balancer. The script will continue. MANUALLY CREATE THE FOLLOWING INBOUND NAT POOL CONFIG ONCE THE SCRIPT COMPLETES. 
                `n$($inboundNatPoolConfig | ConvertTo-Json -Depth 5)$_$_"
            log 'Warning' $message
        }
    }
    log -Message "[InboundNatPoolsMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"

    try {
        $ErrorActionPreference = 'Stop'
        Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer > $null
    }
    catch {
        $message = @"
            [InboundNatPoolsMigration] An error occured when adding Inbound NAT Pool config '$($pool.name)' to the new Standard Load Balancer. The script 
            will continue. MANUALLY CREATE THE FOLLOWING INBOUND NAT POOL CONFIG ONCE THE SCRIPT COMPLETES. 
            `n$($StdLoadBalancer | Get-AzLoadBalancerInboundNatPoolConfig | ConvertTo-Json -Depth 5)$_
"@
        log 'Warning' $message
    }

    $vmss = GetVMSSFromBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer

    _MigrateNetworkInterfaceConfigurations -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -vmss $vmss -refVmss $refVmss

    # Update VMSS on Azure
    UpdateVMSS -vmss $vmss

    # Update Instances
    UpdateVmssInstances -vmss $vmss

    <#
    This will happen in the backend pool migration...
    # Restore VMSS Upgrade Policy Mode
    #_RestoreUpgradePolicyMode -vmss $vmss -refVmss $refVmss

    # Update VMSS on Azure
    #UpdateVMSS -vmss $vmss
    #>

    log -Message "[InboundNatPoolsMigration] Inbound NAT Pools Migration Completed"
}
Export-ModuleMember -Function InboundNatPoolsMigration