
<#PSScriptInfo

.VERSION 1.0

.GUID 188d53d9-5a4a-468a-859d-d448655567b1

.AUTHOR FTA

.COMPANYNAME

.COPYRIGHT

.TAGS

.LICENSEURI

.PROJECTURI

.ICONURI

.EXTERNALMODULEDEPENDENCIES

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES


.PRIVATEDATA

#>

<#

.DESCRIPTION
 This script will migrate a Basic SKU load balancer to a Standard SKU Public load balancer preserving all the configurations.

#>
# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\BackupBasicLoadBalancer\BackupBasicLoadBalancer.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\PublicFEMigration\PublicFEMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\RemoveLBFromVMSS\RemoveLBFromVMSS.psd1")

function AzureVMSSLBUpgrade {
    Param(
        [Parameter(Mandatory = $True)][string] $ResourceGroupName,
        [Parameter(Mandatory = $True)][string] $BasicLoadBalancerName,
        #Parameters for new Standard Load Balancer
        [Parameter(Mandatory = $True)][string] $StdLoadBalancerName
        )

    log -Message "############################## Initializing AzureVMSSLBUpgrade ##############################"

    # Load Azure Resources
    log -Message "[AzureVMSSLBUpgrade] Loading Azure Resources"
    $BasicLoadBalancer = Get-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $BasicLoadBalancerName
    $vmssNames = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.Id | Where-Object{$_ -match "Microsoft.Compute/virtualMachineScaleSets"} | ForEach-Object{$_.split("/")[8]} | Select-Object -Unique
    # Need to fix, it should only return a single unique VMSS even if it has multiple Instances
    #$vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.Id | Where-Object{$_ -match "Microsoft.Compute/virtualMachineScaleSets"} | Select-Object -Unique
    $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object{$_.split("virtualMachines")[0]} | Select-Object -Unique

    # Backup Basic Load Balancer Configurations
    BackupBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer

    # Deletion of Basic Load Balancer
    RemoveLBFromVMSS -vmssIds $vmssIds -BasicLoadBalancer $BasicLoadBalancer

    # Creation of Standard Load Balancer
    $StdLoadBalancerDef = @{
        ResourceGroupName = $ResourceGroupName
        Name = $StdLoadBalancerName
        SKU = "Standard"
        location = $BasicLoadBalancer.Location
    }
    $StdLoadBalancer = New-AzLoadBalancer @StdLoadBalancerDef

    # Migration of Frontend IP Configurations
    PublicFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of NAT Rules

    # *** We need to check InboundNatPools

    # Migration of Backend Address Pools
        # Create empty backend pool with original name
        # Add VMSS network profiles to backend pool

    # Migration of Probes

    # Migration of Load Balancing Rules
        # Use default outbound access configuration **does default outbound use the standard LB public IP (matching the basic LB behavior)?
}

Export-ModuleMember -Function AzureVMSSLBUpgrade