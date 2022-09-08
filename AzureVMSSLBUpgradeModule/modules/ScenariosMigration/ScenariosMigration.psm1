
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
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\BackendPoolMigration\BackendPoolMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\NatRulesMigration\NatRulesMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\InboundNatPoolsMigration\InboundNatPoolsMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\ProbesMigration\ProbesMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\LoadBalacingRulesMigration\LoadBalacingRulesMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\OutboundRulesCreation\OutboundRulesCreation.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\NSGCreation\NSGCreation.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\PrivateFEMigration\PrivateFEMigration.psd1")

function _CreateStandardLoadBalancer {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StdLoadBalancerName
    )

    # Creation of Standard Load Balancer
    log -Message "[_CreateStandardLoadBalancer] Initiating Standard Load Balancer Creation"
    $StdLoadBalancerDef = @{
        ResourceGroupName = $BasicLoadBalancer.ResourceGroupName
        Name = $StdLoadBalancerName
        SKU = "Standard"
        location = $BasicLoadBalancer.Location
    }
    try {
        $ErrorActionPreference = 'Stop'
        $StdLoadBalancer = New-AzLoadBalancer @StdLoadBalancerDef
        log -Message "[_CreateStandardLoadBalancer] Standard Load Balancer $($StdLoadBalancer.Name) created successfully"
        return $StdLoadBalancer
    }
    catch {
        $message = @"
            [_CreateStandardLoadBalancer] An error occured when creating the new Standard load balancer '$StdLoadBalancerName'. To recover,
            redeploy the Basic load balancer from the 'ARMTemplate-$($BasicLoadBalancer.Name)-ResourceGroupName...'
            file, re-add the original backend pool members (see file 'State-$($BasicLoadBalancer.Name)-ResourceGroupName...'
            BackendIpConfigurations), address the following error, and try again. Error message: $_
"@
        log 'Error' $message
        Exit
    }

}

function PublicLBMigration {
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $true)][string] $RecoveryBackupPath
        )

    log -Message "[PublicLBMigration] Public Load Balancer Detected. Initiating Public Load Balancer Migration"
    #$vmssNames = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.Id | Where-Object{$_ -match "Microsoft.Compute/virtualMachineScaleSets"} | ForEach-Object{$_.split("/")[8]} | Select-Object -Unique
    #$vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.Id | Where-Object{$_ -match "Microsoft.Compute/virtualMachineScaleSets"} | Select-Object -Unique
    log -Message "[PublicLBMigration] Loading VMSSs from the Basic Load Balancer"
    $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object{$_.split("virtualMachines")[0]} | Select-Object -Unique

    # Backup Basic Load Balancer Configurations
    BackupBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -RecoveryBackupPath $RecoveryBackupPath

    # Deletion of Basic Load Balancer and Delete Basic Load Balancer
    RemoveLBFromVMSS -vmssIds $vmssIds -BasicLoadBalancer $BasicLoadBalancer

    # Creation of Standard Load Balancer
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Frontend IP Configurations
    PublicFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Backend Address Pools
    BackendPoolMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of NAT Rules
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Inbound NAT Pools
    InboundNatPoolsMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating Outbound Rules for SNAT
    OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer

    # Creating NSG for Standard Load Balancer
    NSGCreation -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer
}

function InternalLBMigration {
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $true)][string] $RecoveryBackupPath
        )

        log -Message "[InternalLBMigration] Internal Load Balancer Detected. Initiating Internal Load Balancer Migration"
        log -Message "[InternalLBMigration] Loading VMSSs from the Basic Load Balancer"
        $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object{$_.split("virtualMachines")[0]} | Select-Object -Unique

        # Backup Basic Load Balancer Configurations
        BackupBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -RecoveryBackupPath $RecoveryBackupPath

        # Deletion of Basic Load Balancer and Delete Basic Load Balancer
        RemoveLBFromVMSS -vmssIds $vmssIds -BasicLoadBalancer $BasicLoadBalancer

        # Creation of Standard Load Balancer
        $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

        # Migration of Private Frontend IP Configurations
        PrivateFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $stdLoadBalancer

        # Migration of Backend Address Pools
        BackendPoolMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Migration of NAT Rules
        NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Migration of Inbound NAT Pools
        InboundNatPoolsMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Migration of Probes
        ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Migration of Load Balancing Rules
        LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Creating Outbound Rules for SNAT
        #OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer

        # Creating NSG for Standard Load Balancer
        #NSGCreation -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

}

function RestoreExternalLBMigration {
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName
        )

        log -Message "[RestoreExternalLBMigration] Restore Public Load Balancer Detected. Initiating Public Load Balancer Migration"
        # Creation of Standard Load Balancer
        $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

        # Migration of Frontend IP Configurations
        PublicFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Migration of Backend Address Pools
        BackendPoolMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Migration of NAT Rules
        NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Migration of Inbound NAT Pools
        InboundNatPoolsMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Migration of Probes
        ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Migration of Load Balancing Rules
        LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Creating Outbound Rules for SNAT
        OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer

        # Creating NSG for Standard Load Balancer
        NSGCreation -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

}

function RestoreInternalLBMigration {
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName
        )

        log -Message "[RestoreInternalLBMigration] Restore Internal Load Balancer Detected. Initiating Internal Load Balancer Migration"
        # Creation of Standard Load Balancer
        $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

        # Migration of Private Frontend IP Configurations
        PrivateFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $stdLoadBalancer

        # Migration of Backend Address Pools
        BackendPoolMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Migration of NAT Rules
        NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Migration of Inbound NAT Pools
        InboundNatPoolsMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Migration of Probes
        ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Migration of Load Balancing Rules
        LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

        # Creating Outbound Rules for SNAT
        #OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer

        # Creating NSG for Standard Load Balancer
        #NSGCreation -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

}

Export-ModuleMember -Function PublicLBMigration
Export-ModuleMember -Function InternalLBMigration
Export-ModuleMember -Function RestoreInternalLBMigration
Export-ModuleMember -Function RestoreExternalLBMigration