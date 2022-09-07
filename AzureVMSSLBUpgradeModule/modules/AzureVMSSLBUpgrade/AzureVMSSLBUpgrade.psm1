
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
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\ScenariosMigration\ScenariosMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\ValidateScenario\ValidateScenario.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\BackupBasicLoadBalancer\BackupBasicLoadBalancer.psd1")

function AzureVMSSLBUpgrade {
    Param(
        [Parameter(Mandatory = $True, ParameterSetName = 'ByName')][string] $ResourceGroupName,
        [Parameter(Mandatory = $True, ParameterSetName = 'ByName')][string] $BasicLoadBalancerName,
        [Parameter(Mandatory = $True, ValueFromPipeline, ParameterSetName = 'ByObject')][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True, ParameterSetName = 'ByJson')][string] $RestoreFromJsonFile,
        [Parameter(Mandatory = $false)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $false)][switch] $FollowLog
        )

    # Set global variable to display log output in console
    If ($FollowLog.IsPresent) {
        $global:FollowLog = $true
    }

    log -Message "############################## Initializing AzureVMSSLBUpgrade ##############################"

    log -Message "[AzureVMSSLBUpgrade] Checking that user is signed in to Azure PowerShell"
    if (!($azContext = Get-AzContext -ErrorAction SilentlyContinue)) {
        log 'Error' "Sign into Azure Powershell with 'Connect-AzAccount' before running this script!"
        return
    }
    log -Message "[AzureVMSSLBUpgrade] User is signed in to Azure with account '$($azContext.Account.Id)'"

    # Load Azure Resources
    log -Message "[AzureVMSSLBUpgrade] Loading Azure Resources"

    try {
        $ErrorActionPreference = 'Stop'
        if (!$PSBoundParameters.ContainsKey("BasicLoadBalancer") -and (!$PSBoundParameters.ContainsKey("RestoreFromJsonFile"))) {
            $BasicLoadBalancer = Get-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $BasicLoadBalancerName
        }
        elseif (!$PSBoundParameters.ContainsKey("BasicLoadBalancer")) {
            $BasicLoadBalancer = RestoreLoadBalancer -BasicLoadBalancerJsonFile $RestoreFromJsonFile
        }
        log -Message "[AzureVMSSLBUpgrade] Basic Load Balancer $($BasicLoadBalancer.Name) loaded"
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

    # verify basic load balancer configuration is a supported scenario
    $StdLoadBalancerName = ($PSBoundParameters.ContainsKey("StandardLoadBalancerName")) ? $StandardLoadBalancerName : $BasicLoadBalancer.Name
    $scenario = Test-SupportedMigrationScenario -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancerName

    # Migration of Frontend IP Configurations
    switch ($scenario.ExternalOrInternal) {
        'internal' {
            if ((!$PSBoundParameters.ContainsKey("RestoreFromJsonFile"))) {
                InternalLBMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancerName
            }
            else {
                RestoreInternalLBMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancerName
            }
        }
        'external' {
            if ((!$PSBoundParameters.ContainsKey("RestoreFromJsonFile"))) {
                PublicLBMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancerName
            }
            else {
                RestoreExternalLBMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StdLoadBalancerName
            }
        }
    }
    log -Message "############################## Migration Completed ##############################"
}

Export-ModuleMember -Function AzureVMSSLBUpgrade