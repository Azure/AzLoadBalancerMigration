
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

function AzureVMSSLBUpgrade {
    Param(
        [Parameter(Mandatory = $True)][string] $ResourceGroupName,
        [Parameter(Mandatory = $True)][string] $BasicLoadBalancerName,
        #Parameters for new Standard Load Balancer
        # *** We still need to decide if we will allow the user to change the name of the LB or use the same name***
        [Parameter(Mandatory = $false)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $false)][switch] $FollowLog
        )

    # Set global variable to display log output in console
    If ($FollowLog.IsPresent) {
        $global:FollowLog = $true
    }

    log -Message "############################## Initializing AzureVMSSLBUpgrade ##############################"

    # Load Azure Resources
    log -Message "[AzureVMSSLBUpgrade] Loading Azure Resources"

    try {
        $ErrorActionPreference = 'Stop'
        $BasicLoadBalancer = Get-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $BasicLoadBalancerName
    }
    catch {
        $message = @"
            [AzureVMSSLBUpgrade] Failed to find basic load balancer '$BasicLoadBalancerName' in resource group '$ResourceGroupName' under subscription
            '$((Get-AzContext).Subscription.Name)'. Ensure that the correct subscription is selected and verify the load balancer and resource group names.
            Error text: $_
"@
        log -severity Error -message $message

        Exit
    }
    #$vmssNames = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.Id | Where-Object{$_ -match "Microsoft.Compute/virtualMachineScaleSets"} | ForEach-Object{$_.split("/")[8]} | Select-Object -Unique
    #$vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.Id | Where-Object{$_ -match "Microsoft.Compute/virtualMachineScaleSets"} | Select-Object -Unique
    $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object{$_.split("virtualMachines")[0]} | Select-Object -Unique

    # Backup Basic Load Balancer Configurations
    BackupBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer

    # Deletion of Basic Load Balancer and Delete Basic Load Balancer
    RemoveLBFromVMSS -vmssIds $vmssIds -BasicLoadBalancer $BasicLoadBalancer

    # Creation of Standard Load Balancer
    $StdLoadBalancerName = ($PSBoundParameters.ContainsKey("StandardLoadBalancerName")) ? $StandardLoadBalancerName : $BasicLoadBalancerName
    $StdLoadBalancerDef = @{
        ResourceGroupName = $ResourceGroupName
        Name = $StdLoadBalancerName
        SKU = "Standard"
        location = $BasicLoadBalancer.Location
    }
    try {
        $ErrorActionPreference = 'Stop'
        $StdLoadBalancer = New-AzLoadBalancer @StdLoadBalancerDef
    }
    catch {
        $message = @"
            [AzureVMSSLBUpgrade] An error occured when creating the new Standard load balancer '$StdLoadBalancerName'. To recover,
            redeploy the Basic load balancer from the 'ARMTemplate-$BasicLoadBalancerName-ResourceGroupName...'
            file, re-add the original backend pool members (see file 'State-$BasicLoadBalancerName-ResourceGroupName...'
            BackendIpConfigurations), address the following error, and try again. Error message: $_
"@
        log 'Error' $message
        Exit
    }

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
        # *** Use default outbound access configuration **does default outbound use the standard LB public IP (matching the basic LB behavior)?
        # We need to check if we will create an outbound rule for the Standard LB or not
    LoadBalacingRulesMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    # Creating Outbound Rules for SNAT
    OutboundRulesCreation -StdLoadBalancer $StdLoadBalancer

    # Creating NSG for Standard Load Balancer
    NSGCreation -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer

    log -Message "############################## Migration Completed ##############################"
}

Export-ModuleMember -Function AzureVMSSLBUpgrade