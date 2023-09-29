
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
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/AddLoadBalancerBackendAddressPool/AddLoadBalancerBackendAddressPool.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/BackendPoolMigration/BackendPoolMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/BackupBasicLoadBalancer/BackupBasicLoadBalancer.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/GetVmssFromBasicLoadBalancer/GetVmssFromBasicLoadBalancer.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/InboundNatPoolsMigration/InboundNatPoolsMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/LoadBalacingRulesMigration/LoadBalacingRulesMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/NatRulesMigration/NatRulesMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/NsgCreation/NsgCreation.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/OutboundRulesCreation/OutboundRulesCreation.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/PrivateFEMigration/PrivateFEMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/ProbesMigration/ProbesMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/PublicFEMigration/PublicFEMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/RemoveBasicLoadBalancer/RemoveBasicLoadBalancer.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/ValidateMigration/ValidateMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/VMPublicIPConfigMigration/VMPublicIPConfigMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/VmssPublicIPConfigMigration/VmssPublicIPConfigMigration.psd1")

function _CreateStandardLoadBalancer {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StdLoadBalancerName
    )

    # Creation of Standard Load Balancer
    log -Message "[_CreateStandardLoadBalancer] Initiating Standard Load Balancer Creation"
    $StdLoadBalancerDef = @{
        ResourceGroupName = $BasicLoadBalancer.ResourceGroupName
        Name              = $StdLoadBalancerName
        SKU               = "Standard"
        location          = $BasicLoadBalancer.Location
        Tag               = $BasicLoadBalancer.Tag
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
        log 'Error' $message -terminateOnError
    }

}

function PublicLBMigrationVmss {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $true)][string] $RecoveryBackupPath,
        [Parameter(Mandatory = $true)][psobject] $scenario,
        [Parameter(Mandatory = $false)][switch]$outputMigrationValiationObj
    )

    log -Message "[PublicLBMigration] Public Load Balancer with VMSS backend found. Initiating Public Load Balancer Migration"

    # Creating a vmss object before it gets changed as a reference for the backend pool migration
    $refVmss = GetVmssFromBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer

    # Backup Basic Load Balancer Configurations
    BackupBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -RecoveryBackupPath $RecoveryBackupPath

    # Backup VMSS Configurations
    BackupVmss -BasicLoadBalancer $BasicLoadBalancer -RecoveryBackupPath $RecoveryBackupPath

    # Remove Public IP Configurations from VMSS
    RemoveVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer

    # Migrate public IP addresses on Basic LB to static (if dynamic)
    PublicIPToStatic -BasicLoadBalancer $BasicLoadBalancer

    # Deletion of Basic Load Balancer and Delete Basic Load Balancer
    RemoveBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -BackendType 'VMSS'
    
    # Add Public IP Configurations to VMSS (with Standard SKU)
    AddVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer -refVmss $refVmss

    # Creation of Standard Load Balancer
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Frontend IP Configurations
    PublicFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating Outbound Rules for SNAT
    OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer -Scenario $scenario

    # Migration of NAT Rules
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Inbound NAT Pools
    InboundNatPoolsMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # Creating NSG for Standard Load Balancer
    NsgCreationVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Backend Address Pools
    BackendPoolMigrationVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    ValidateMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancer.Name -outputMigrationValiationObj:$outputMigrationValiationObj
}

function InternalLBMigrationVmss {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $true)][string] $RecoveryBackupPath,
        [Parameter(Mandatory = $true)][psobject] $scenario,
        [Parameter(Mandatory = $false)][switch]$outputMigrationValiationObj
    )

    log -Message "[InternalLBMigration] Internal Load Balancer with VMSS backend detected. Initiating Internal Load Balancer Migration"

    # Creating a vmss object before it gets changed as a reference for the backend pool migration
    $refVmss = GetVmssFromBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer

    # Backup Basic Load Balancer Configurations
    BackupBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -RecoveryBackupPath $RecoveryBackupPath

    # Backup VMSS Configurations
    BackupVmss -BasicLoadBalancer $BasicLoadBalancer -RecoveryBackupPath $RecoveryBackupPath

    # Remove Public IP Configurations from VMSS
    RemoveVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer

    # Deletion of Basic Load Balancer and Delete Basic Load Balancer
    RemoveBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -BackendType 'VMSS'

    # Add Public IP Configurations to VMSS (with Standard SKU)
    AddVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer -refVmss $refVmss

    # Creation of Standard Load Balancer
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Private Frontend IP Configurations
    PrivateFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $stdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of NAT Rules
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Inbound NAT Pools
    InboundNatPoolsMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # Migration of Backend Address Pools
    BackendPoolMigrationVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # Creating Outbound Rules for SNAT
    #OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer -Scenario $scenario

    # Creating NSG for Standard Load Balancer
    #NsgCreationVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    ValidateMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancer.Name -outputMigrationValiationObj:$outputMigrationValiationObj
}

function RestoreExternalLBMigrationVmss {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $vmss,
        [Parameter(Mandatory = $true)][psobject] $scenario,
        [Parameter(Mandatory = $false)][switch]$outputMigrationValiationObj
    )

    log -Message "[RestoreExternalLBMigration] Restore Public Load Balancer with VMSS backend detected. Initiating Public Load Balancer Migration"

    # Creating a vmss object before it gets changed as a reference for the backend pool migration
    $refVmss = $vmss

    # Remove Public IP Configurations from VMSS
    RemoveVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer

    # Migrate public IP addresses on Basic LB to static (if dynamic)
    PublicIPToStatic -BasicLoadBalancer $BasicLoadBalancer

    # Add Public IP Configurations to VMSS
    AddVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer -refVmss $refVmss

    # Creation of Standard Load Balancer
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Frontend IP Configurations
    PublicFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating Outbound Rules for SNAT
    OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer -Scenario $scenario

    # Migration of NAT Rules
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Inbound NAT Pools
    InboundNatPoolsMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # Creating NSG for Standard Load Balancer
    NsgCreationVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Backend Address Pools
    BackendPoolMigrationVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    ValidateMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancer.Name -outputMigrationValiationObj:$outputMigrationValiationObj
}

function RestoreInternalLBMigrationVmss {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $vmss,
        [Parameter(Mandatory = $true)][psobject] $scenario,
        [Parameter(Mandatory = $false)][switch]$outputMigrationValiationObj
    )

    log -Message "[RestoreInternalLBMigration] Restore Internal Load Balancer with VMSS backend detected. Initiating Internal Load Balancer Migration"

    # Creating a vmss object before it gets changed as a reference for the backend pool migration
    $refVmss = $vmss

    # Remove Public IP Configurations from VMSS
    RemoveVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer

    # Add Public IP Configurations to VMSS (with Standard SKU)
    AddVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer -refVmss $refVmss

    # Creation of Standard Load Balancer
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Private Frontend IP Configurations
    PrivateFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $stdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of NAT Rules
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Inbound NAT Pools
    InboundNatPoolsMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # Migration of Backend Address Pools
    BackendPoolMigrationVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # Creating Outbound Rules for SNAT
    #OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer -Scenario $scenario

    # Creating NSG for Standard Load Balancer
    #NsgCreationVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    ValidateMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancer.Name -outputMigrationValiationObj:$outputMigrationValiationObj
}

function PublicLBMigrationVM {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $true)][string] $RecoveryBackupPath,
        [Parameter(Mandatory = $true)][psobject] $scenario,
        [Parameter(Mandatory = $false)][switch]$outputMigrationValiationObj
    )

    log -Message "[PublicLBMigrationVM] Public Load Balancer with VM backend detected. Initiating Public Load Balancer Migration"

    # Backup Basic Load Balancer Configurations
    BackupBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -RecoveryBackupPath $RecoveryBackupPath

    # Migrate public IP addresses on Basic LB to static (if dynamic)
    PublicIPToStatic -BasicLoadBalancer $BasicLoadBalancer

    # Deletion of Basic Load Balancer and Delete Basic Load Balancer
    RemoveBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -BackendType 'VM'

    # Upgrade VMs Public IPs to Standard SKU
    UpgradeVMPublicIP -BasicLoadBalancer $BasicLoadBalancer

    # Creation of Standard Load Balancer
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Frontend IP Configurations
    PublicFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating Outbound Rules for SNAT
    OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer -Scenario $scenario

    # Migration of NAT Rules
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating NSG for Standard Load Balancer
    NsgCreationVM -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Backend Address Pools
    BackendPoolMigrationVM -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    ValidateMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancer.Name -outputMigrationValiationObj:$outputMigrationValiationObj
}

function InternalLBMigrationVM {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $true)][string] $RecoveryBackupPath,
        [Parameter(Mandatory = $true)][psobject] $scenario,
        [Parameter(Mandatory = $false)][switch]$outputMigrationValiationObj
    )

    log -Message "[InternalLBMigrationVM] Internal Load Balancer with VM backend detected. Initiating Internal Load Balancer Migration"

    # Backup Basic Load Balancer Configurations
    BackupBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -RecoveryBackupPath $RecoveryBackupPath

    # Deletion of Basic Load Balancer and Delete Basic Load Balancer
    RemoveBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -BackendType 'VM'

    # Upgrade VMs Public IPs to Standard SKU
    UpgradeVMPublicIP -BasicLoadBalancer $BasicLoadBalancer

    # Creation of Standard Load Balancer
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Private Frontend IP Configurations
    PrivateFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $stdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of NAT Rules
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Backend Address Pools
    BackendPoolMigrationVM -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer
    
    # validate the new standard load balancer configuration against the original basic load balancer configuration
    ValidateMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancer.Name -outputMigrationValiationObj:$outputMigrationValiationObj
}

function RestoreExternalLBMigrationVM {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $true)][psobject] $scenario,
        [Parameter(Mandatory = $false)][switch]$outputMigrationValiationObj
    )

    log -Message "[RestoreExternalLBMigration] Restore Public Load Balancer with VM backend detected. Initiating Public Load Balancer Migration"

    # Migrate public IP addresses on Basic LB to static (if dynamic)
    PublicIPToStatic -BasicLoadBalancer $BasicLoadBalancer

    # Creation of Standard Load Balancer
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Frontend IP Configurations
    PublicFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating Outbound Rules for SNAT
    OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer -Scenario $scenario

    # Migration of NAT Rules
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating NSG for Standard Load Balancer
    NsgCreationVm -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Backend Address Pools
    BackendPoolMigrationVm -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    ValidateMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancer.Name -outputMigrationValiationObj:$outputMigrationValiationObj
}

function RestoreInternalLBMigrationVM {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $true)][psobject] $scenario,
        [Parameter(Mandatory = $false)][switch]$outputMigrationValiationObj
    )

    log -Message "[RestoreInternalLBMigration] Restore Internal Load Balancer with VM backend detected. Initiating Internal Load Balancer Migration"

    # Creation of Standard Load Balancer
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Private Frontend IP Configurations
    PrivateFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $stdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of NAT Rules
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Backend Address Pools
    BackendPoolMigrationVM -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating Outbound Rules for SNAT
    #OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer -Scenario $scenario

    # Creating NSG for Standard Load Balancer
    #NsgCreationVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    ValidateMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancer.Name -outputMigrationValiationObj:$outputMigrationValiationObj
}

function PublicLBMigrationEmpty {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $true)][string] $RecoveryBackupPath,
        [Parameter(Mandatory = $true)][psobject] $scenario,
        [Parameter(Mandatory = $false)][switch]$outputMigrationValiationObj
    )

    log -Message "[PublicLBMigrationEmpty] Public Load Balancer with empty detected. Initiating Public Load Balancer Migration"

    # Backup Basic Load Balancer Configurations
    BackupBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -RecoveryBackupPath $RecoveryBackupPath

    # Migrate public IP addresses on Basic LB to static (if dynamic)
    PublicIPToStatic -BasicLoadBalancer $BasicLoadBalancer

    # Deletion of Basic Load Balancer and Delete Basic Load Balancer
    RemoveBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -BackendType 'Empty'

    # Creation of Standard Load Balancer
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Frontend IP Configurations
    PublicFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating Outbound Rules for SNAT
    OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer -Scenario $scenario

    # Migration of NAT Rules
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    ValidateMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancer.Name -outputMigrationValiationObj:$outputMigrationValiationObj
}

function InternalLBMigrationEmpty {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $true)][string] $RecoveryBackupPath,
        [Parameter(Mandatory = $true)][psobject] $scenario,
        [Parameter(Mandatory = $false)][switch]$outputMigrationValiationObj
    )

    log -Message "[InternalLBMigrationEmpty] Internal Load Balancer with empty detected. Initiating Internal Load Balancer Migration"

    # Backup Basic Load Balancer Configurations
    BackupBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -RecoveryBackupPath $RecoveryBackupPath

    # Deletion of Basic Load Balancer and Delete Basic Load Balancer
    RemoveBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -BackendType 'Empty'

    # Creation of Standard Load Balancer
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Private Frontend IP Configurations
    PrivateFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $stdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of NAT Rules
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    ValidateMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancer.Name -outputMigrationValiationObj:$outputMigrationValiationObj
}

function RestoreExternalLBMigrationEmpty {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $true)][psobject] $scenario,
        [Parameter(Mandatory = $false)][switch]$outputMigrationValiationObj
    )

    log -Message "[RestoreExternalLBMigration] Restore Public Load Balancer with empty detected. Initiating Public Load Balancer Migration"

    # Migrate public IP addresses on Basic LB to static (if dynamic)
    PublicIPToStatic -BasicLoadBalancer $BasicLoadBalancer

    # Creation of Standard Load Balancer
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Frontend IP Configurations
    PublicFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating Outbound Rules for SNAT
    OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer -Scenario $scenario

    # Migration of NAT Rules
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    ValidateMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancer.Name -outputMigrationValiationObj:$outputMigrationValiationObj
}

function RestoreInternalLBMigrationEmpty {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $true)][psobject] $scenario,
        [Parameter(Mandatory = $false)][switch]$outputMigrationValiationObj
    )

    log -Message "[RestoreInternalLBMigration] Restore Internal Load Balancer with empty detected. Initiating Internal Load Balancer Migration"

    # Creation of Standard Load Balancer
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Private Frontend IP Configurations
    PrivateFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $stdLoadBalancer
Vmss
    # Add Backend Pool to Standard Load Balancer
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of NAT Rules
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    ValidateMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancer.Name -outputMigrationValiationObj:$outputMigrationValiationObj
}

Export-ModuleMember -Function PublicLBMigrationVmss
Export-ModuleMember -Function InternalLBMigrationVmss
Export-ModuleMember -Function RestoreInternalLBMigrationVmss
Export-ModuleMember -Function RestoreExternalLBMigrationVmss
Export-ModuleMember -Function PublicLBMigrationVM
Export-ModuleMember -Function InternalLBMigrationVM
Export-ModuleMember -Function RestoreInternalLBMigrationVM
Export-ModuleMember -Function RestoreExternalLBMigrationVM
Export-ModuleMember -Function PublicLBMigrationEmpty
Export-ModuleMember -Function InternalLBMigrationEmpty
Export-ModuleMember -Function RestoreInternalLBMigrationEmpty
Export-ModuleMember -Function RestoreExternalLBMigrationEmpty
