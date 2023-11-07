
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
        [Parameter(Mandatory = $false)][switch]$outputMigrationValiationObj,
        [Parameter(Mandatory = $false)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $refVmss
    )

    $progressParams = @{
        Activity = "Migrating basic load balancer '$($BasicLoadBalancer.Name)'"
        ParentId = 4
    }

    Write-Progress -Status "Public Load Balancer with VMSS backend detected. Initiating Public Load Balancer Migration" -PercentComplete 0 @progressParams
    log -Message "[PublicLBMigration] Public Load Balancer with VMSS backend found. Initiating Public Load Balancer Migration"

    # Creating a vmss object before it gets changed as a reference for the backend pool migration
    Write-Progress -Status "Backing up VMSS" -ParentId 4 @progressParams

    # Backup VMSS Configurations
    BackupVmss -BasicLoadBalancer $BasicLoadBalancer -RecoveryBackupPath $RecoveryBackupPath

    # Remove Public IP Configurations from VMSS
    Write-Progress -Status "Removing Public IP Configurations from VMSS" -PercentComplete ((1 / 14) * 100) @progressParams
    RemoveVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer

    # Migrate public IP addresses on Basic LB to static (if dynamic)
    Write-Progress -Activity "Migrating public IP addresses on Basic LB to static (if dynamic)" -PercentComplete ((2 / 14) * 100) @progressParams
    PublicIPToStatic -BasicLoadBalancer $BasicLoadBalancer
    
    # Add Public IP Configurations to VMSS (with Standard SKU)
    Write-Progress -Status "Adding Public IP Configurations to VMSS (with Standard SKU)" -PercentComplete ((3 / 14) * 100) @progressParams
    AddVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer -refVmss $refVmss

    # Creation of Standard Load Balancer
    Write-Progress -Status "Creating Standard Load Balancer" -PercentComplete ((4 / 14) * 100) @progressParams
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Frontend IP Configurations
    Write-Progress -Status "Migrating Frontend IP Configurations" -PercentComplete ((5 / 14) * 100) @progressParams
    PublicFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    Write-Progress -Status "Adding Backend Pool to Standard Load Balancer" -PercentComplete ((6 / 14) * 100) @progressParams
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    Write-Progress -Status "Migrating Probes" -PercentComplete ((7 / 14) * 100) @progressParams
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    Write-Progress -Status "Migrating Load Balancing Rules" -PercentComplete ((8 / 14) * 100) @progressParams
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating Outbound Rules for SNAT
    Write-Progress -Status "Creating Outbound Rules for SNAT" -PercentComplete ((9 / 14) * 100) @progressParams
    OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer -Scenario $scenario

    # Migration of NAT Rules
    Write-Progress -Status "Migrating NAT Rules" -PercentComplete ((10 / 14) * 100) @progressParams
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Inbound NAT Pools
    Write-Progress -Status "Migrating Inbound NAT Pools" -PercentComplete ((11 / 14) * 100) @progressParams
    InboundNatPoolsMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # Creating NSG for Standard Load Balancer
    Write-Progress -Status "Creating NSG for Standard Load Balancer" -PercentComplete ((12 / 14) * 100) @progressParams
    NsgCreationVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Backend Address Pools
    Write-Progress -Status "Migrating Backend Address Pools" -PercentComplete ((13 / 14) * 100) @progressParams
    BackendPoolMigrationVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    Write-Progress -Status "Validating the new standard load balancer configuration against the original basic load balancer configuration" -Completed @progressParams
    ValidateMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancer.Name -outputMigrationValiationObj:$outputMigrationValiationObj
}

function InternalLBMigrationVmss {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $true)][string] $RecoveryBackupPath,
        [Parameter(Mandatory = $true)][psobject] $scenario,
        [Parameter(Mandatory = $false)][switch]$outputMigrationValiationObj,
        [Parameter(Mandatory = $false)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $refVmss
    )

    $progressParams = @{
        Activity = "Migrating basic load balancer '$($BasicLoadBalancer.Name)'"
        ParentId = 4
    }

    log -Message "[InternalLBMigration] Internal Load Balancer with VMSS backend detected. Initiating Internal Load Balancer Migration"

    # Creating a vmss object before it gets changed as a reference for the backend pool migration
    Write-Progress -Status "Backing up VMSS" -PercentComplete ((1/14) * 100) @progressParams

    # Backup VMSS Configurations
    Write-Progress -Status "Backing up VMSS Configurations" -PercentComplete ((2/14) * 100) @progressParams
    BackupVmss -BasicLoadBalancer $BasicLoadBalancer -RecoveryBackupPath $RecoveryBackupPath

    # Remove Public IP Configurations from VMSS
    Write-Progress -Status "Removing Public IP Configurations from VMSS" -PercentComplete ((3/14) * 100) @progressParams
    RemoveVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer

    # Add Public IP Configurations to VMSS (with Standard SKU)
    Write-Progress -Status "Adding Public IP Configurations to VMSS (with Standard SKU)" -PercentComplete ((4/14) * 100) @progressParams
    AddVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer -refVmss $refVmss

    # Creation of Standard Load Balancer
    Write-Progress -Status "Creating Standard Load Balancer" -PercentComplete ((5/14) * 100) @progressParams
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Private Frontend IP Configurations
    Write-Progress -Status "Migrating Private Frontend IP Configurations" -PercentComplete ((6/14) * 100) @progressParams
    PrivateFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $stdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    Write-Progress -Status "Adding Backend Pool to Standard Load Balancer" -PercentComplete ((7/14) * 100) @progressParams
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    Write-Progress -Status "Migrating Probes" -PercentComplete ((8/14) * 100) @progressParams
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    Write-Progress -Status "Migrating Load Balancing Rules" -PercentComplete ((9/14) * 100) @progressParams
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of NAT Rules
    Write-Progress -Status "Migrating NAT Rules" -PercentComplete ((10/14) * 100) @progressParams
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Inbound NAT Pools
    Write-Progress -Status "Migrating Inbound NAT Pools" -PercentComplete ((11/14) * 100) @progressParams
    InboundNatPoolsMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # Migration of Backend Address Pools
    Write-Progress -Status "Migrating Backend Address Pools" -PercentComplete ((12/14) * 100) @progressParams
    BackendPoolMigrationVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    Write-Progress -Status "Validating the new standard load balancer configuration against the original basic load balancer configuration" -Completed @progressParams
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

    $progressParams = @{
        Activity = "Migrating basic load balancer '$($BasicLoadBalancer.Name)'"
        ParentId = 4
    }

    log -Message "[RestoreExternalLBMigration] Restore Public Load Balancer with VMSS backend detected. Initiating Public Load Balancer Migration"

    # Creating a vmss object before it gets changed as a reference for the backend pool migration
    $refVmss = $vmss

    # Remove Public IP Configurations from VMSS
    Write-Progress -Status "Removing Public IP Configurations from VMSS" -PercentComplete ((1/14) * 100) @progressParams
    RemoveVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer

    # Migrate public IP addresses on Basic LB to static (if dynamic)
    Write-Progress -Status "Migrating public IP addresses on Basic LB to static (if dynamic)" -PercentComplete ((2/14) * 100) @progressParams
    PublicIPToStatic -BasicLoadBalancer $BasicLoadBalancer

    # Add Public IP Configurations to VMSS
    Write-Progress -Status "Adding Public IP Configurations to VMSS" -PercentComplete ((3/14) * 100) @progressParams
    AddVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer -refVmss $refVmss

    # Creation of Standard Load Balancer
    Write-Progress -Status "Creating Standard Load Balancer" -PercentComplete ((4/14) * 100) @progressParams
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Frontend IP Configurations
    Write-Progress -Status "Migrating Frontend IP Configurations" -PercentComplete ((5/14) * 100) @progressParams
    PublicFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    Write-Progress -Status "Adding Backend Pool to Standard Load Balancer" -PercentComplete ((6/14) * 100) @progressParams
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    Write-Progress -Status "Migrating Probes" -PercentComplete ((7/14) * 100) @progressParams
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    Write-Progress -Status "Migrating Load Balancing Rules" -PercentComplete ((8/14) * 100) @progressParams
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating Outbound Rules for SNAT
    Write-Progress -Status "Creating Outbound Rules for SNAT" -PercentComplete ((9/14) * 100) @progressParams
    OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer -Scenario $scenario

    # Migration of NAT Rules
    Write-Progress -Status "Migrating NAT Rules" -PercentComplete ((10/14) * 100) @progressParams
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Inbound NAT Pools
    Write-Progress -Status "Migrating Inbound NAT Pools" -PercentComplete ((11/14) * 100) @progressParams
    InboundNatPoolsMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # Creating NSG for Standard Load Balancer
    Write-Progress -Status "Creating NSG for Standard Load Balancer" -PercentComplete ((12/14) * 100) @progressParams
    NsgCreationVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Backend Address Pools
    Write-Progress -Status "Migrating Backend Address Pools" -PercentComplete ((13/14) * 100) @progressParams
    BackendPoolMigrationVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    Write-Progress -Status "Validating the new standard load balancer configuration against the original basic load balancer configuration" -Completed @progressParams
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

    $progressParams = @{
        Activity = "Migrating basic load balancer '$($BasicLoadBalancer.Name)'"
        ParentId = 4
    }

    log -Message "[RestoreInternalLBMigration] Restore Internal Load Balancer with VMSS backend detected. Initiating Internal Load Balancer Migration"

    # Creating a vmss object before it gets changed as a reference for the backend pool migration
    $refVmss = $vmss

    # Remove Public IP Configurations from VMSS
    Write-Progress -Status "Removing Public IP Configurations from VMSS" -PercentComplete ((1/14) * 100) @progressParams
    RemoveVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer

    # Add Public IP Configurations to VMSS (with Standard SKU)
    Write-Progress -Status "Adding Public IP Configurations to VMSS (with Standard SKU)" -PercentComplete ((2/14) * 100) @progressParams
    AddVmssPublicIPConfig -BasicLoadBalancer $BasicLoadBalancer -refVmss $refVmss

    # Creation of Standard Load Balancer
    Write-Progress -Status "Creating Standard Load Balancer" -PercentComplete ((3/14) * 100) @progressParams
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Private Frontend IP Configurations
    Write-Progress -Status "Migrating Private Frontend IP Configurations" -PercentComplete ((4/14) * 100) @progressParams
    PrivateFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $stdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    Write-Progress -Status "Adding Backend Pool to Standard Load Balancer" -PercentComplete ((5/14) * 100) @progressParams
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    Write-Progress -Status "Migrating Probes" -PercentComplete ((6/14) * 100) @progressParams
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    Write-Progress -Status "Migrating Load Balancing Rules" -PercentComplete ((7/14) * 100) @progressParams
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of NAT Rules
    Write-Progress -Status "Migrating NAT Rules" -PercentComplete ((8/14) * 100) @progressParams
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Inbound NAT Pools
    Write-Progress -Status "Migrating Inbound NAT Pools" -PercentComplete ((9/14) * 100) @progressParams
    InboundNatPoolsMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # Migration of Backend Address Pools
    Write-Progress -Status "Migrating Backend Address Pools" -PercentComplete ((10/14) * 100) @progressParams
    BackendPoolMigrationVmss -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer -refVmss $refVmss

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    Write-Progress -Status "Validating the new standard load balancer configuration against the original basic load balancer configuration" -Completed @progressParams
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

    $progressParams = @{
        Activity = "Migrating basic load balancer '$($BasicLoadBalancer.Name)'"
        ParentId = 4
    }

    log -Message "[PublicLBMigrationVM] Public Load Balancer with VM backend detected. Initiating Public Load Balancer Migration"

    # Upgrade VMs Public IPs to Standard SKU
    Write-Progress -Status "Upgrading VMs Public IPs to Standard SKU" -PercentComplete ((1 / 14) * 100) @progressParams
    UpgradeVMPublicIP -BasicLoadBalancer $BasicLoadBalancer

    # Creation of Standard Load Balancer
    Write-Progress -Status "Creating Standard Load Balancer" -PercentComplete ((2 / 14) * 100) @progressParams
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Frontend IP Configurations
    Write-Progress -Status "Migrating Frontend IP Configurations" -PercentComplete ((3 / 14) * 100) @progressParams
    PublicFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    Write-Progress -Status "Adding Backend Pool to Standard Load Balancer" -PercentComplete ((4 / 14) * 100) @progressParams
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    Write-Progress -Status "Migrating Probes" -PercentComplete ((5 / 14) * 100) @progressParams
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    Write-Progress -Status "Migrating Load Balancing Rules" -PercentComplete ((6 / 14) * 100) @progressParams
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating Outbound Rules for SNAT
    Write-Progress -Status "Creating Outbound Rules for SNAT" -PercentComplete ((7 / 14) * 100) @progressParams
    OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer -Scenario $scenario

    # Migration of NAT Rules
    Write-Progress -Status "Migrating NAT Rules" -PercentComplete ((8 / 14) * 100) @progressParams
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating NSG for Standard Load Balancer
    Write-Progress -Status "Creating NSG for Standard Load Balancer" -PercentComplete ((9 / 14) * 100) @progressParams
    NsgCreationVM -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Backend Address Pools
    Write-Progress -Status "Migrating Backend Address Pools" -PercentComplete ((10 / 14) * 100) @progressParams
    BackendPoolMigrationVM -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    Write-Progress -Status "Validating the new standard load balancer configuration against the original basic load balancer configuration" -Completed @progressParams
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

    $progressParams = @{
        Activity = "Migrating basic load balancer '$($BasicLoadBalancer.Name)'"
        ParentId = 4
    }

    log -Message "[InternalLBMigrationVM] Internal Load Balancer with VM backend detected. Initiating Internal Load Balancer Migration"

    # Upgrade VMs Public IPs to Standard SKU
    Write-Progress -Status "Upgrading VMs Public IPs to Standard SKU" -PercentComplete ((1 / 14) * 100) @progressParams
    UpgradeVMPublicIP -BasicLoadBalancer $BasicLoadBalancer

    # Creation of Standard Load Balancer
    Write-Progress -Status "Creating Standard Load Balancer" -PercentComplete ((2 / 14) * 100) @progressParams
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Private Frontend IP Configurations
    Write-Progress -Status "Migrating Private Frontend IP Configurations" -PercentComplete ((3 / 14) * 100) @progressParams
    PrivateFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $stdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    Write-Progress -Status "Adding Backend Pool to Standard Load Balancer" -PercentComplete ((4 / 14) * 100) @progressParams
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    Write-Progress -Status "Migrating Probes" -PercentComplete ((5 / 14) * 100) @progressParams
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    Write-Progress -Status "Migrating Load Balancing Rules" -PercentComplete ((6 / 14) * 100) @progressParams
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of NAT Rules
    Write-Progress -Status "Migrating NAT Rules" -PercentComplete ((7 / 14) * 100) @progressParams
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Backend Address Pools
    Write-Progress -Status "Migrating Backend Address Pools" -PercentComplete ((8 / 14) * 100) @progressParams
    BackendPoolMigrationVM -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer
    
    # validate the new standard load balancer configuration against the original basic load balancer configuration
    Write-Progress -Status "Validating the new standard load balancer configuration against the original basic load balancer configuration" -Completed @progressParams
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

    $ProgressParams = @{
        Activity = "Migrating basic load balancer '$($BasicLoadBalancer.Name)'"
        ParentId = 4
    }

    log -Message "[RestoreExternalLBMigration] Restore Public Load Balancer with VM backend detected. Initiating Public Load Balancer Migration"

    # Migrate public IP addresses on Basic LB to static (if dynamic)
    Write-Progress -Status "Migrating public IP addresses on Basic LB to static (if dynamic)" -PercentComplete ((1 / 14) * 100) @progressParams
    PublicIPToStatic -BasicLoadBalancer $BasicLoadBalancer

    # Creation of Standard Load Balancer
    Write-Progress -Status "Creating Standard Load Balancer" -PercentComplete ((2 / 14) * 100) @progressParams
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Frontend IP Configurations
    Write-Progress -Status "Migrating Frontend IP Configurations" -PercentComplete ((3 / 14) * 100) @progressParams
    PublicFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    Write-Progress -Status "Adding Backend Pool to Standard Load Balancer" -PercentComplete ((4 / 14) * 100) @progressParams
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    Write-Progress -Status "Migrating Probes" -PercentComplete ((5 / 14) * 100) @progressParams
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    Write-Progress -Status "Migrating Load Balancing Rules" -PercentComplete ((6 / 14) * 100) @progressParams
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating Outbound Rules for SNAT
    Write-Progress -Status "Creating Outbound Rules for SNAT" -PercentComplete ((7 / 14) * 100) @progressParams
    OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer -Scenario $scenario

    # Migration of NAT Rules
    Write-Progress -Status "Migrating NAT Rules" -PercentComplete ((8 / 14) * 100) @progressParams
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating NSG for Standard Load Balancer
    Write-Progress -Status "Creating NSG for Standard Load Balancer" -PercentComplete ((9 / 14) * 100) @progressParams
    NsgCreationVm -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Backend Address Pools
    Write-Progress -Status "Migrating Backend Address Pools" -PercentComplete ((10 / 14) * 100) @progressParams
    BackendPoolMigrationVm -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    Write-Progress -Status "Validating the new standard load balancer configuration against the original basic load balancer configuration" -Completed @progressParams
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

    $progressParams = @{
        Activity = "Migrating basic load balancer '$($BasicLoadBalancer.Name)'"
        ParentId = 4
    }

    log -Message "[RestoreInternalLBMigration] Restore Internal Load Balancer with VM backend detected. Initiating Internal Load Balancer Migration"

    # Creation of Standard Load Balancer
    Write-Progress -Status "Creating Standard Load Balancer" -PercentComplete ((1 / 14) * 100) @progressParams
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Private Frontend IP Configurations
    Write-Progress -Status "Migrating Private Frontend IP Configurations" -PercentComplete ((2 / 14) * 100) @progressParams
    PrivateFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $stdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    Write-Progress -Status "Adding Backend Pool to Standard Load Balancer" -PercentComplete ((3 / 14) * 100) @progressParams
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    Write-Progress -Status "Migrating Probes" -PercentComplete ((4 / 14) * 100) @progressParams
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    Write-Progress -Status "Migrating Load Balancing Rules" -PercentComplete ((5 / 14) * 100) @progressParams
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of NAT Rules
    Write-Progress -Status "Migrating NAT Rules" -PercentComplete ((6 / 14) * 100) @progressParams
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Backend Address Pools
    Write-Progress -Status "Migrating Backend Address Pools" -PercentComplete ((7 / 14) * 100) @progressParams
    BackendPoolMigrationVM -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    Write-Progress -Status "Validating the new standard load balancer configuration against the original basic load balancer configuration" -Completed @progressParams
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

    $progressParams = @{
        Activity = "Migrating basic load balancer '$($BasicLoadBalancer.Name)'"
        ParentId = 4
    }

    log -Message "[PublicLBMigrationEmpty] Public Load Balancer with empty detected. Initiating Public Load Balancer Migration"

    # Creation of Standard Load Balancer
    Write-Progress -Status "Creating Standard Load Balancer" -PercentComplete ((1/14) * 100) @progressParams
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Frontend IP Configurations
    Write-Progress -Status "Migrating Frontend IP Configurations" -PercentComplete ((2/14) * 100) @progressParams
    PublicFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    Write-Progress -Status "Adding Backend Pool to Standard Load Balancer" -PercentComplete ((3/14) * 100) @progressParams
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    Write-Progress -Status "Migrating Probes" -PercentComplete ((4/14) * 100) @progressParams
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    Write-Progress -Status "Migrating Load Balancing Rules" -PercentComplete ((5/14) * 100) @progressParams
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating Outbound Rules for SNAT
    Write-Progress -Status "Creating Outbound Rules for SNAT" -PercentComplete ((6/14) * 100) @progressParams
    OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer -Scenario $scenario

    # Migration of NAT Rules
    Write-Progress -Status "Migrating NAT Rules" -PercentComplete ((7/14) * 100) @progressParams
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    Write-Progress -Status "Validating the new standard load balancer configuration against the original basic load balancer configuration" -Completed @progressParams
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

    $progressParams = @{
        Activity = "Migrating basic load balancer '$($BasicLoadBalancer.Name)'"
        ParentId = 4
    }

    log -Message "[InternalLBMigrationEmpty] Internal Load Balancer with empty detected. Initiating Internal Load Balancer Migration"

    # Backup Basic Load Balancer Configurations
    Write-Progress -Status "Backup Basic Load Balancer Configurations" -PercentComplete ((1/14) * 100) @progressParams
    BackupBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -RecoveryBackupPath $RecoveryBackupPath

    # Deletion of Basic Load Balancer and Delete Basic Load Balancer
    Write-Progress -Status "Deletion of Basic Load Balancer and Delete Basic Load Balancer" -PercentComplete ((2/14) * 100) @progressParams
    RemoveBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -BackendType 'Empty'

    # Creation of Standard Load Balancer
    Write-Progress -Status "Creation of Standard Load Balancer" -PercentComplete ((3/14) * 100) @progressParams
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Private Frontend IP Configurations
    Write-Progress -Status "Migrating Private Frontend IP Configurations" -PercentComplete ((4/14) * 100) @progressParams
    PrivateFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $stdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    Write-Progress -Status "Add Backend Pool to Standard Load Balancer" -PercentComplete ((5/14) * 100) @progressParams
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    Write-Progress -Status "Migrating Probes" -PercentComplete ((6/14) * 100) @progressParams
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    Write-Progress -Status "Migrating Load Balancing Rules" -PercentComplete ((7/14) * 100) @progressParams
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of NAT Rules
    Write-Progress -Status "Migrating NAT Rules" -PercentComplete ((8/14) * 100) @progressParams
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    Write-Progress -Status "Validating the new standard load balancer configuration against the original basic load balancer configuration" -Completed @progressParams
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

    $progressParams = @{
        Activity = "Migrating basic load balancer '$($BasicLoadBalancer.Name)'"
        ParentId = 4
    }

    log -Message "[RestoreExternalLBMigration] Restore Public Load Balancer with empty detected. Initiating Public Load Balancer Migration"

    # Migrate public IP addresses on Basic LB to static (if dynamic)
    Write-Progress -Status "Migrating public IP addresses on Basic LB to static (if dynamic)" -PercentComplete ((1/14) * 100) @progressParams
    PublicIPToStatic -BasicLoadBalancer $BasicLoadBalancer

    # Creation of Standard Load Balancer
    Write-Progress -Status "Creation of Standard Load Balancer" -PercentComplete ((2/14) * 100) @progressParams
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Frontend IP Configurations
    Write-Progress -Status "Migrating Frontend IP Configurations" -PercentComplete ((3/14) * 100) @progressParams
    PublicFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Add Backend Pool to Standard Load Balancer
    Write-Progress -Status "Add Backend Pool to Standard Load Balancer" -PercentComplete ((4/14) * 100) @progressParams
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    Write-Progress -Status "Migrating Probes" -PercentComplete ((5/14) * 100) @progressParams
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    Write-Progress -Status "Migrating Load Balancing Rules" -PercentComplete ((6/14) * 100) @progressParams
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating Outbound Rules for SNAT
    Write-Progress -Status "Creating Outbound Rules for SNAT" -PercentComplete ((7/14) * 100) @progressParams
    OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer -Scenario $scenario

    # Migration of NAT Rules
    Write-Progress -Status "Migrating NAT Rules" -PercentComplete ((8/14) * 100) @progressParams
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    Write-Progress -Status "Validating the new standard load balancer configuration against the original basic load balancer configuration" -Completed @progressParams
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

    $progressParams = @{
        Activity = "Migrating basic load balancer '$($BasicLoadBalancer.Name)'"
        ParentId = 4
    }

    log -Message "[RestoreInternalLBMigration] Restore Internal Load Balancer with empty detected. Initiating Internal Load Balancer Migration"

    # Creation of Standard Load Balancer
    Write-Progress -Status "Creation of Standard Load Balancer" -PercentComplete ((1/14) * 100) @progressParams
    $StdLoadBalancer = _CreateStandardLoadBalancer -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName $StandardLoadBalancerName

    # Migration of Private Frontend IP Configurations
    Write-Progress -Status "Migrating Private Frontend IP Configurations" -PercentComplete ((2/14) * 100) @progressParams
    PrivateFEMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $stdLoadBalancer
    
    # Add Backend Pool to Standard Load Balancer
    Write-Progress -Status "Add Backend Pool to Standard Load Balancer" -PercentComplete ((3/14) * 100) @progressParams
    AddLoadBalancerBackendAddressPool -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Probes
    Write-Progress -Status "Migrating Probes" -PercentComplete ((4/14) * 100) @progressParams
    ProbesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of Load Balancing Rules
    Write-Progress -Status "Migrating Load Balancing Rules" -PercentComplete ((5/14) * 100) @progressParams
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Migration of NAT Rules
    Write-Progress -Status "Migrating NAT Rules" -PercentComplete ((6/14) * 100) @progressParams
    NatRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # validate the new standard load balancer configuration against the original basic load balancer configuration
    Write-Progress -Status "Validating the new standard load balancer configuration against the original basic load balancer configuration" -Completed @progressParams
    ValidateMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancer.Name -outputMigrationValiationObj:$outputMigrationValiationObj
}

function LBMigrationPrep {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [psobject[]]
        $migrationConfigs,
        [Parameter(Mandatory = $true)]
        [string]
        $RecoveryBackupPath
    )

    $ErrorActionPreference = 'Stop' 

    ForEach ($migrationConfig in $migrationConfigs) {
        log -message "[LBMigrationPrep] Preparing load balancer '$($migrationConfig.BasicLoadBalancer.Name)' for migration"
        $progressParams = @{
            Activity = "Preparing load balancer '$($migrationConfig.BasicLoadBalancer.Name)' for migration"
            Parent                   = 3
        }
        Write-Progress -Status "Preparing load balancer '$($migrationConfig.BasicLoadBalancer.Name)' for migration" -PercentComplete ((1/4) * 100) @progressParams

        # Backup Basic Load Balancer Configurations
        Write-Progress -Status "Backing up Basic Load Balancer Configurations" -PercentComplete ((2/4) * 100) @progressParams
        BackupBasicLoadBalancer -BasicLoadBalancer $migrationConfig.BasicLoadBalancer -RecoveryBackupPath $RecoveryBackupPath

        # get a reference copy of the vmss prior to modifying it
        If ($migrationConfig.scenario.backendType -eq 'VMSS') {
            $migrationConfig['vmssRefObject'] = GetVmssFromBasicLoadBalancer -BasicLoadBalancer $migrationConfig.BasicLoadBalancer
        }

        If ($migrationConfig.scenario.ExternalOrInternal -eq 'External') {
            # Migrate public IP addresses on Basic LB to static (if dynamic)
            Write-Progress -Status "Migrating public IP addresses on Basic LB to static (if dynamic)" -PercentComplete ((3/4) * 100) @progressParams
            PublicIPToStatic -BasicLoadBalancer $migrationConfig.BasicLoadBalancer
        }

        # Deletion of Basic Load Balancer and Delete Basic Load Balancer
        Write-Progress -Status "Deletion of Basic Load Balancer and Delete Basic Load Balancer" -PercentComplete ((4/4) * 100) -Completed @progressParams
        RemoveBasicLoadBalancer -BasicLoadBalancer $migrationConfig.BasicLoadBalancer -BackendType $migrationConfig.scenario.backendType

        log -message "[LBMigrationPrep] Completed preparing load balancer '$($migrationConfig.BasicLoadBalancer.Name)' for migration"
    }

    # return the migration configs with the reference vmss object
    return $migrationConfigs
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
Export-ModuleMember -Function LBMigrationPrep
