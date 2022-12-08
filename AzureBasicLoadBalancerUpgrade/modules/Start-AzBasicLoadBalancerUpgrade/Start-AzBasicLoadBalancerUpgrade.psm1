
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
 This module will migrate a Basic SKU load balancer connected to a Virtual Machine Scaleset (VMSS) to a Standard SKU load balancer, preserving the existing configuration and functionality.

.SYNOPSIS
This module consists of a number of child modules which abstract the operations required to successfully migrate a Basic to a Standard load balancer.
A Basic Load Balancer cannot be natively migrate to a Standard SKU, therefore this module creates a new Standard laod balancer based on the configuration of the existing Basic load balancer.

Unsupported scenarios:
- Basic load balancers with a VMSS backend pool member which is also a member of a backend pool on a different load balancer
- Basic load balancers with backend pool members which are not a VMSS
- Basic load balancers with only empty backend pools
- Basic load balancers with IPV6 frontend IP configurations
- Basic load balancers with a VMSS backend pool member configured with 'Flexible' orchestration mode
- Basic load balancers with a VMSS backend pool member where one or more VMSS instances have ProtectFromScaleSetActions Instance Protection policies enabled
- Migrating a Basic load balancer to an existing Standard load balancer

.OUTPUTS
This module outputs the following files on execution:
  - Start-AzBasicLoadBalancerUpgrade.log: in the directory where the script is executed, this file contains a log of the migration operation. Refer to it for error details in a failed migration.
  - 'ARMTemplate_<basicLBName>_<basicLBRGName>_<timestamp>.json: either in the directory where the script is executed or the path specified with -RecoveryBackupPath. This is an ARM template for the basic LB, for reference only.
  - 'State_<basicLBName>_<basicLBRGName>_<timestamp>.json: either in the directory where the script is executed or the path specified with -RecoveryBackupPath. This is a state backup of the basic LB, used in retry scenarios.
  - 'VMSS_<vmssName>_<vmssRGName>_<timestamp>.json: either in the directory where the script is executed or the path specified with -RecoveryBackupPath. This is a state backup of the VMSS, used in retry scenarios.

.EXAMPLE
# Basic usage
PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName myRG -BasicLoadBalancerName myBasicLB

.EXAMPLE
# Pass LoadBalancer via pipeline input
PS C:\> Get-AzLoadBalancer -ResourceGroupName myRG -Name myBasicLB | Start-AzBasicLoadBalancerUpgrade -StandardLoadBalancerName myStandardLB

.EXAMPLE
# Pass LoadBalancer via pipeline input and re-use the existing Load Balancer Name
PS C:\> Get-AzLoadBalancer -ResourceGroupName myRG -Name myBasicLB | Start-AzBasicLoadBalancerUpgrade

.EXAMPLE
# Pass LoadBalancer object using -BasicLoadBalancer parameter input and re-use the existing Load Balancer Name
PS C:\> $basicLB = Get-AzLoadBalancer -ResourceGroupName myRG -Name myBasicLB
PS C:\> Start-AzBasicLoadBalancerUpgrade -BasicLoadBalancer $basicLB

.EXAMPLE
# Specify a custom path for recovery backup files
PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName myRG -BasicLoadBalancerName myBasicLB -RecoveryBackupPath C:\RecoveryBackups

.EXAMPLE
# Retry a failed migration
PS C:\> Start-AzBasicLoadBalancerUpgrade -FailedMigrationRetryFilePathLB C:\RecoveryBackups\State_mybasiclb_rg-basiclbrg_20220912T1740032148.json -FailedMigrationRetryFilePathVMSS C:\RecoveryBackups\VMSS_myVMSS_rg-basiclbrg_20220912T1740032148.json

.EXAMPLE
# display logs in the console as the command executes
PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName myRG -BasicLoadBalancerName myBasicLB -FollowLog

.PARAMETER ResourceGroupName
Resource group containing the Basic Load Balancer to migrate. The new Standard load balancer will be created in this resource group.

.PARAMETER BasicLoadBalancerName
Name of the existing Basic Load Balancer to migrate

.PARAMETER BasicLoadBalancer
Load Balancer object to migrate passed as pipeline input or parameter

.PARAMETER FailedMigrationRetryFilePathLB
Location of a Basic load balancer backup file (used when retrying a failed migration or manual configuration comparison)

.PARAMETER FailedMigrationRetryFilePathVMSS
Location of a VMSS backup file (used when retrying a failed migration or manual configuration comparison)

.PARAMETER StandardLoadBalancerName
Name of the new Standard Load Balancer. If not specified, the name of the Basic load balancer will be reused.

.PARAMETER RecoveryBackupPath
Location of the Recovery backup files

.PARAMETER FollowLog
Switch parameter to enable the display of logs in the console

#>

# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\ScenariosMigration\ScenariosMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\ValidateScenario\ValidateScenario.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\BackupBasicLoadBalancer\BackupBasicLoadBalancer.psd1")

function Start-AzBasicLoadBalancerUpgrade {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True, ParameterSetName = 'ByName')][string] $ResourceGroupName,
        [Parameter(Mandatory = $True, ParameterSetName = 'ByName')][string] $BasicLoadBalancerName,
        [Parameter(Mandatory = $True, ValueFromPipeline, ParameterSetName = 'ByObject')][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True, ParameterSetName = 'ByJson')][string] $FailedMigrationRetryFilePathLB,
        [Parameter(Mandatory = $True, ParameterSetName = 'ByJson')][string] $FailedMigrationRetryFilePathVMSS,
        [Parameter(Mandatory = $false)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $false)][string] $RecoveryBackupPath = $pwd,
        [Parameter(Mandatory = $false)][switch] $FollowLog
        )

    # Set global variable to display log output in console
    If ($FollowLog.IsPresent) {
        $global:FollowLog = $true
    }

    # validate backup path is directory
    If (!(Test-Path -Path $RecoveryBackupPath -PathType Container )) {
        Write-Error "The path '$recoveryBackupPath' specified with parameter recoveryBackupPath must exist and be a valid directory." -terminateOnError
    }

    log -Message "############################## Initializing Start-AzBasicLoadBalancerUpgrade ##############################"

    log -Message "[Start-AzBasicLoadBalancerUpgrade] Checking that user is signed in to Azure PowerShell"
    if (!($azContext = Get-AzContext -ErrorAction SilentlyContinue)) {
        log 'Error' "Sign into Azure Powershell with 'Connect-AzAccount' before running this script!"
        return
    }
    log -Message "[Start-AzBasicLoadBalancerUpgrade] User is signed in to Azure with account '$($azContext.Account.Id)', subscription '$($azContext.Subscription.Name)' selected"

    # Load Azure Resources
    log -Message "[Start-AzBasicLoadBalancerUpgrade] Loading Azure Resources"

    try {
        $ErrorActionPreference = 'Stop'
        if (!$PSBoundParameters.ContainsKey("BasicLoadBalancer") -and (!$PSBoundParameters.ContainsKey("FailedMigrationRetryFilePathLB"))) {
            $BasicLoadBalancer = Get-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $BasicLoadBalancerName
        }
        elseif (!$PSBoundParameters.ContainsKey("BasicLoadBalancer")) {
            $BasicLoadBalancer = RestoreLoadBalancer -BasicLoadBalancerJsonFile $FailedMigrationRetryFilePathLB
            $vmss = RestoreVMSS -VMSSJsonFile $FailedMigrationRetryFilePathVMSS
        }
        log -Message "[Start-AzBasicLoadBalancerUpgrade] Basic Load Balancer $($BasicLoadBalancer.Name) loaded"
    }
    catch {
        $message = @"
            [Start-AzBasicLoadBalancerUpgrade] Failed to find basic load balancer '$BasicLoadBalancerName' in resource group '$ResourceGroupName' under subscription
            '$((Get-AzContext).Subscription.Name)'. Ensure that the correct subscription is selected and verify the load balancer and resource group names.
            Error text: $_
"@
        log -severity Error -message $message -terminateOnError
    }

    # verify basic load balancer configuration is a supported scenario
    # Ternary operator is only supported in PowerShell 7 and above to keep compatibility with PowerShell 5.1, we use the If statement
    #$StdLoadBalancerName = ($PSBoundParameters.ContainsKey("StandardLoadBalancerName")) ? $StandardLoadBalancerName : $BasicLoadBalancer.Name
    if($PSBoundParameters.ContainsKey("StandardLoadBalancerName")){
        $StdLoadBalancerName = $StandardLoadBalancerName
    }
    else{
        $StdLoadBalancerName = $BasicLoadBalancer.Name
    }

    $scenario = Test-SupportedMigrationScenario -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancerName

    # Migration of Frontend IP Configurations
    switch ($scenario.ExternalOrInternal) {
        'internal' {
            if ((!$PSBoundParameters.ContainsKey("FailedMigrationRetryFilePathLB"))) {
                InternalLBMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancerName -RecoveryBackupPath $RecoveryBackupPath
            }
            else {
                RestoreInternalLBMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancerName -vmss $vmss
            }
        }
        'external' {
            if ((!$PSBoundParameters.ContainsKey("FailedMigrationRetryFilePathLB"))) {
                PublicLBMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancerName -RecoveryBackupPath $RecoveryBackupPath
            }
            else {
                RestoreExternalLBMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancerName -vmss $vmss
            }
        }
    }
    log -Message "############################## Migration Completed ##############################"
}

Export-ModuleMember -Function Start-AzBasicLoadBalancerUpgrade