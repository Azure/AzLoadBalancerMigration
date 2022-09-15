
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
 This module will migrate a Basic SKU load balancer connected to a Virtual Machine Scaleset (VMSS) to a Standard SKU load balancer preserving the existing configuration.

.SYNOPSIS
This module consists of a number of child modules which abstract the operations required to successfully upgrade a Basic to a Standard load balancer.
A Basic Load Balancer cannot be natively upgraded to a Standard SKU, therefore this module creates a new Standard laod balancer based on the configuration of the existing Basic load balancer.

.EXAMPLE
# Basic usage
PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName myRG -BasicLoadBalancerName myBasicLB

.EXAMPLE
# Pass LoadBalancer via pipeline input
PS C:\> Get-AzLoadBalancer -ResourceGroupName myRG -Name myBasicLB | Start-AzBasicLoadBalancerUpgrade -StandardLoadBalancerName myStandardLB

.EXAMPLE
# Specify a custom path for recovery backup files
PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName myRG -BasicLoadBalancerName myBasicLB -RecoveryBackupPath C:\RecoveryBackups

.EXAMPLE
# Retry a failed migration
PS C:\> Start-AzBasicLoadBalancerUpgrade -FailedMigrationRetryFilePath C:\RecoveryBackups\State_mybasiclb_rg-basiclbrg_20220912T1740032148.json

.EXAMPLE
# display logs in the console as the command executes
PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName myRG -BasicLoadBalancerName myBasicLB -FollowLog

.PARAMETER ResourceGroupName
Resource group containing the Basic Load Balancer to upgrade

.PARAMETER BasicLoadBalancerName
Name of the Basic Load Balancer to upgrade

.PARAMETER BasicLoadBalancer
Load Balancer Object to upgrade passed as pipeline input

.PARAMETER FailedMigrationRetryFilePath
Location of a Basic load balancer backup state file (used when retrying a failed migration)

.PARAMETER StandardLoadBalancerName
Name of the new Standard Load Balancer

.PARAMETER RecoveryBackupPath
Location of the Recovery backup files

.PARAMETER FollowLog
Swtich parameter to enable the display of logs in the console

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
        [Parameter(Mandatory = $True, ParameterSetName = 'ByJson')][string] $FailedMigrationRetryFilePath,
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
        Write-Error "The path '$recoveryBackupPath' specified with parameter recoveryBackupPath must exist and be a valid directory."
        Exit
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
        if (!$PSBoundParameters.ContainsKey("BasicLoadBalancer") -and (!$PSBoundParameters.ContainsKey("FailedMigrationRetryFilePath"))) {
            $BasicLoadBalancer = Get-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $BasicLoadBalancerName
        }
        elseif (!$PSBoundParameters.ContainsKey("BasicLoadBalancer")) {
            $BasicLoadBalancer = RestoreLoadBalancer -BasicLoadBalancerJsonFile $FailedMigrationRetryFilePath
        }
        log -Message "[Start-AzBasicLoadBalancerUpgrade] Basic Load Balancer $($BasicLoadBalancer.Name) loaded"
    }
    catch {
        $message = @"
            [Start-AzBasicLoadBalancerUpgrade] Failed to find basic load balancer '$BasicLoadBalancerName' in resource group '$ResourceGroupName' under subscription
            '$((Get-AzContext).Subscription.Name)'. Ensure that the correct subscription is selected and verify the load balancer and resource group names.
            Error text: $_
"@
        log -severity Error -message $message

        Exit
    }

    # verify basic load balancer configuration is a supported scenario
    $StdLoadBalancerName = ($PSBoundParameters.ContainsKey("StandardLoadBalancerName")) ? $StandardLoadBalancerName : $BasicLoadBalancer.Name
    $scenario = Test-SupportedMigrationScenario -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancerName

    # Migration of Frontend IP Configurations
    switch ($scenario.ExternalOrInternal) {
        'internal' {
            if ((!$PSBoundParameters.ContainsKey("FailedMigrationRetryFilePath"))) {
                InternalLBMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancerName -RecoveryBackupPath $RecoveryBackupPath
            }
            else {
                RestoreInternalLBMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancerName
            }
        }
        'external' {
            if ((!$PSBoundParameters.ContainsKey("FailedMigrationRetryFilePath"))) {
                PublicLBMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancerName -RecoveryBackupPath $RecoveryBackupPath
            }
            else {
                RestoreExternalLBMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancerName
            }
        }
    }
    log -Message "############################## Migration Completed ##############################"
}

Export-ModuleMember -Function Start-AzBasicLoadBalancerUpgrade