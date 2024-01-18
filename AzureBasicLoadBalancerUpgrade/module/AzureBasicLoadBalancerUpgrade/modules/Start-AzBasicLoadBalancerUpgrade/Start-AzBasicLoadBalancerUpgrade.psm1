# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\ScenariosMigration\ScenariosMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\ValidateScenario\ValidateScenario.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\ValidateMigration\ValidateMigration.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\BackupResources\BackupResources.psd1")

<#
.SYNOPSIS
    This module will migrate a Basic SKU load balancer connected to a Virtual Machine Scaleset (VMSS) or Virtual Machine(s) to a Standard SKU load balancer, preserving the existing configuration and functionality.

.DESCRIPTION
    This module consists of a number of child modules which abstract the operations required to successfully migrate a Basic to a Standard load balancer.
    A Basic Load Balancer cannot be natively migrate to a Standard SKU, therefore this module creates a new Standard laod balancer based on the configuration of the existing Basic load balancer.

    Unsupported scenarios:
    - Basic load balancers with backend pool members which are not VMs or a VMSS
    - Basic load balancers with IPV6 frontend IP configurations
    - Basic load balancers with a VMSS backend pool member where one or more VMSS instances have ProtectFromScaleSetActions Instance Protection policies enabled
    - Migrating a Basic load balancer to an existing Standard load balancer

    Multi-load balancer support:
    In a situation where multiple Basic load balancers are configured with the same backend pool members (internal and external load balancers), the migration can be performed in a single operation by specifying the 
    -MultiLBConfig parameter. This option deletes all specified basic load balancers before starting the migration, then creates new standard load balancers mirroring the basic load balancer configurations. 

    Recovering from a failed migration:
    The module takes a backup of the basic load balancer configuration, which can be used to retry a failed migration. The backup files are stored in the directory where the script is executed, or in the directory 
    specified with the -RecoveryBackupPath parameter.

    In a multi-load balancer migration, recovery in performed on a per-load balancer basis--attempt to retry the migration of each load balancer individually.

.PARAMETER ResourceGroupName
    Resource group containing the Basic Load Balancer to migrate. The new Standard load balancer will be created in this resource group.

.PARAMETER BasicLoadBalancerName
    Name of the existing Basic Load Balancer to migrate

.PARAMETER BasicLoadBalancer
    Load Balancer object to migrate passed as pipeline input or parameter

.PARAMETER basicLoadBalancerStatePath
Use in combination with -validateCompletedMigration to validate a completed migration

.PARAMETER FailedMigrationRetryFilePathLB
    Location of a Basic load balancer backup file (used when retrying a failed migration or manual configuration comparison)

.PARAMETER FailedMigrationRetryFilePathVMSS
    Location of a VMSS backup file (used when retrying a failed migration or manual configuration comparison)

.PARAMETER outputMigrationValiationObj
    Switch parameter to output the migration validation object to the console - useful for large scale and pipeline migrations

.PARAMETER StandardLoadBalancerName
    Name of the new Standard Load Balancer. If not specified, the name of the Basic load balancer will be reused.

.PARAMETER skipUpgradeNATPoolsToNATRules
    If specified, the migration will skip upgrading NAT Pools to NAT Rules. NAT Rules are more managable and functional than NAT Pools, while providing the same functionality

.PARAMETER MultiLBConfig
    Array of objects containing the basic load balancer and standard load balancer name to migrate. Use this parameter to migrate multiple load balancers with shared backend pool members. Optionally, specify a new standard load balancer name for each basic load balancers.
    Example value: $multiLBConfig = @(
        @{
            'standardLoadBalancerName' = 'myStandardLB01'
            'basicLoadBalancer' = (Get-AzLoadBalancer -ResourceGroupName myRG -Name myBasicLB01)
        },
            @{
            'standardLoadBalancerName' = 'myStandardLB02'
            'basicLoadBalancer' = (Get-AzLoadBalancer -ResourceGroupName myRG -Name myBasicLB02)
        }
    )

.PARAMETER RecoveryBackupPath
    Location of the Recovery backup files

.PARAMETER FollowLog
    Switch parameter to enable the display of logs in the console

.PARAMETER validateScenarioOnly
    Only perform the validation portion of the migration, then exit the script without making changes

.PARAMETER validateCompletedMigration
    Using the exported Basic Load Balancer state file, validate the migration was completed successfully

.OUTPUTS
    This module outputs the following files on execution:
    - Start-AzBasicLoadBalancerUpgrade.log: in the directory where the script is executed, this file contains a log of the migration operation. Refer to it for error details in a failed migration.
    - 'ARMTemplate_<basicLBName>_<basicLBRGName>_<timestamp>.json: either in the directory where the script is executed or the path specified with -RecoveryBackupPath. This is an ARM template for the basic LB, for reference only.
    - 'State_<basicLBName>_<basicLBRGName>_<timestamp>.json: either in the directory where the script is executed or the path specified with -RecoveryBackupPath. This is a state backup of the basic LB, used in retry scenarios.
    - 'State_VMSS_<vmssName>_<vmssRGName>_<timestamp>.json: either in the directory where the script is executed or the path specified with -RecoveryBackupPath. This is a state backup of the VMSS, used in retry scenarios.

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
    # migrate multiple load balancers with shared backend pool members
    PS C:\> $multiLBConfig = @(
        @{
            'basicLoadBalancer' = (Get-AzLoadBalancer -ResourceGroupName myRG -Name myBasicLB01)
            'standardLoadBalancerName' = 'myStandardLB01'       # optional new standard load balancer name
        },
            @{
            'basicLoadBalancer' = (Get-AzLoadBalancer -ResourceGroupName myRG -Name myBasicLB02)
            'standardLoadBalancerName' = 'myStandardLB02'
        }
    )
    PS C:\> Start-AzBasicLoadBalancerUpgrade -MultiLBConfig $multiLBConfig

.EXAMPLE
    # Retry a failed VMSS migration
    PS C:\> Start-AzBasicLoadBalancerUpgrade -FailedMigrationRetryFilePathLB C:\RecoveryBackups\State_mybasiclb_rg-basiclbrg_20220912T1740032148.json -FailedMigrationRetryFilePathVMSS C:\RecoveryBackups\VMSS_myVMSS_rg-basiclbrg_20220912T1740032148.json

.EXAMPLE
    # Retry a failed VM migration
    PS C:\> Start-AzBasicLoadBalancerUpgrade -FailedMigrationRetryFilePathLB C:\RecoveryBackups\State_mybasiclb_rg-basiclbrg_20220912T1740032148.json

.EXAMPLE
    # display logs in the console as the command executes
    PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName myRG -BasicLoadBalancerName myBasicLB -FollowLog

.EXAMPLE
    # validate a completed migration using the exported Basic Load Balancer state file. Add -StandardLoadBalancerName to validate against a Standard Load Balancer with a different name than the Basic Load Balancer
    PS C:\> Start-AzBasicLoadBalancerUpgrade -validateCompletedMigration -basicLoadBalancerStatePath C:\RecoveryBackups\State_mybasiclb_rg-basiclbrg_20220912T1740032148.json

.LINK 
    https://github.com/Azure/AzLoadBalancerMigration/tree/main/AzureBasicLoadBalancerUpgrade

.LINK
    https://learn.microsoft.com/azure/load-balancer/upgrade-basic-standard-with-powershell
#>
function Start-AzBasicLoadBalancerUpgrade {
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    Param(
        [Parameter(Mandatory = $True, ParameterSetName = 'ByName')][string] $ResourceGroupName, 
        [Parameter(Mandatory = $True, ParameterSetName = 'ByName')][string] $BasicLoadBalancerName,
        [Parameter(Mandatory = $True, ValueFromPipeline, ParameterSetName = 'ByObject')][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True, ParameterSetName = 'ByJsonVm')][string] 
        [Parameter(Mandatory = $True, ParameterSetName = 'ByJsonVmss')][string]
        $FailedMigrationRetryFilePathLB,
        [Parameter(Mandatory = $True, ParameterSetName = 'ByJsonVmss')][string] $FailedMigrationRetryFilePathVMSS,
        [Parameter(Mandatory = $false, ParameterSetName = 'ValidateCompletedMigration')][string]
        [Parameter(Mandatory = $false, ParameterSetName = 'ByName')][string]
        [Parameter(Mandatory = $false, ParameterSetName = 'ByObject')][string]
        [Parameter(Mandatory = $false, ParameterSetName = 'ByJsonVm')][string] 
        [Parameter(Mandatory = $false, ParameterSetName = 'ByJsonVmss')][string] 
        $StandardLoadBalancerName,
        [Parameter(Mandatory = $false)][string] $RecoveryBackupPath = $pwd,
        [Parameter(Mandatory = $false)][switch] $FollowLog,
        [Parameter(Mandatory = $false)][switch] $validateScenarioOnly,
        [Parameter(Mandatory = $True, ParameterSetName = 'MultiLB')][psobject[]] $multiLBConfig, # @(@{basicLoadBalancer=<[Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]>[;standardLoadBalancerName='lb-standard-01']})
        [Parameter(Mandatory = $false, ParameterSetName = 'ByName')][switch]
        [Parameter(Mandatory = $false, ParameterSetName = 'ByObject')][switch]
        [Parameter(Mandatory = $false, ParameterSetName = 'ByJsonVmss')][switch] 
        [Parameter(Mandatory = $false, ParameterSetName = 'MultiLB')][switch] 
        [Parameter(Mandatory = $false, ParameterSetName = 'ValidateCompletedMigration')][switch]
        $skipUpgradeNATPoolsToNATRules,
        [Parameter(Mandatory = $true, ParameterSetName = 'ValidateCompletedMigration')][switch] $validateCompletedMigration,
        [Parameter(Mandatory = $true, ParameterSetName = 'ValidateCompletedMigration')][string] $basicLoadBalancerStatePath,
        [Parameter(Mandatory = $false)][switch] $outputMigrationValiationObj,
        [Parameter(Mandatory = $false)][int32] $defaultJobWaitTimeout = (New-Timespan -Minutes 10).TotalSeconds,
        [Parameter(Mandatory = $false)][switch] $force,
        [Parameter(Mandatory = $false)][switch] $Pre
    )

    # Set global variable to display log output in console
    If ($FollowLog.IsPresent) {
        $global:FollowLog = $true
    }

    # Default to -FollowLogs if running in Cloud Shell to avoid timeouts
    If ($env:POWERSHELL_DISTRIBUTION_CHANNEL -eq 'CloudShell') {
        $global:FollowLog = $true
    }

    # Set global variable for default job wait timoue
    $global:defaultJobWaitTimeout = $defaultJobWaitTimeout

    # validate backup path is directory
    If (!(Test-Path -Path $RecoveryBackupPath -PathType Container )) {
        Write-Error "The path '$recoveryBackupPath' specified with parameter recoveryBackupPath must exist and be a valid directory." -terminateOnError
    }

    log -Message "############################## Initializing Start-AzBasicLoadBalancerUpgrade ##############################"

    log -Message "[Start-AzBasicLoadBalancerUpgrade] PowerShell Version: $($PSVersionTable.PSVersion.ToString())"
    log -Message "[Start-AzBasicLoadBalancerUpgrade] AzureBasicLoadBalancerUpgrade Version: $((Get-Module -Name AzureBasicLoadBalancerUpgrade).Version.ToString())"

    log -Message "[Start-AzBasicLoadBalancerUpgrade] Checking that user is signed in to Azure PowerShell"
    if (!($azContext = Get-AzContext -ErrorAction SilentlyContinue)) {
        log -Severity 'Error' -Message "Sign into Azure Powershell with 'Connect-AzAccount' before running this script!"
        return
    }
    log -Message "[Start-AzBasicLoadBalancerUpgrade] User is signed in to Azure with account '$($azContext.Account.Id)', subscription '$($azContext.Subscription.Name)' selected"

    ### validate a completed migration ###
    if ($validateCompletedMigration) {
        log -Message "[Start-AzBasicLoadBalancerUpgrade] Validating completed migration using basic LB state file '$basicLoadBalancerStatePath' and standard load balancer name '$StandardLoadBalancerName'"

        # import basic LB from file
        $BasicLoadBalancer = RestoreLoadBalancer -BasicLoadBalancerJsonFile $basicLoadBalancerStatePath

        ValidateMigration -BasicLoadBalancer $BasicLoadBalancer -StandardLoadBalancerName $StandardLoadBalancerName -OutputMigrationValiationObj:$($OutputMigrationValiationObj.IsPresent) -natPoolsMigratedToNatRules:(!$skipUpgradeNATPoolsToNATRules)

        return
    }

    ### initiate a new or recovery migration ###
    # Load Azure Resources
    Write-Progress -Activity "Loading Azure Resources" -Status "Loading Azure Resources" -Id 1
    log -Message "[Start-AzBasicLoadBalancerUpgrade] Loading Azure Resources"

    try {
        $ErrorActionPreference = 'Stop'
        if (!$PSBoundParameters.ContainsKey("BasicLoadBalancer") -and (!$PSBoundParameters.ContainsKey("FailedMigrationRetryFilePathLB")) -and ($PSCmdlet.ParameterSetName -ne 'MultiLB')) {
            $BasicLoadBalancer = Get-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $BasicLoadBalancerName
        }
        elseif (!$PSBoundParameters.ContainsKey("BasicLoadBalancer") -and ($PSBoundParameters.ContainsKey("FailedMigrationRetryFilePathVMSS"))) {
            
            # recover VMSS migration from backup state files
            $BasicLoadBalancer = RestoreLoadBalancer -BasicLoadBalancerJsonFile $FailedMigrationRetryFilePathLB
            $vmss = RestoreVmss -VMSSJsonFile $FailedMigrationRetryFilePathVMSS
        }
        elseIf (($PSBoundParameters.ContainsKey("FailedMigrationRetryFilePathLB") -and (!$PSBoundParameters.ContainsKey("FailedMigrationRetryFilePathVMSS")))) {
            
            #recovery VM migration from backup state file
            $BasicLoadBalancer = RestoreLoadBalancer -BasicLoadBalancerJsonFile $FailedMigrationRetryFilePathLB
        }

        If ($PSCmdlet.ParameterSetName -ne 'MultiLB') {
            log -Message "[Start-AzBasicLoadBalancerUpgrade] Basic Load Balancer '$($BasicLoadBalancer.Name)' in Resource Group '$($basicLoadBalancer.ResourceGroupName)' loaded"
        }
    }
    catch {
        $message = "[Start-AzBasicLoadBalancerUpgrade] Failed to find basic load balancer '$BasicLoadBalancerName' in resource group '$ResourceGroupName' under subscription '$((Get-AzContext).Subscription.Name)'. Ensure that the correct subscription is selected and verify the load balancer and resource group names. Error text: $_"
        log -severity Error -message $message -terminateOnError
    }

    Write-Progress -Activity "Loading Azure Resources" -Status "Loading Azure Resources" -Completed -Id 1

    # verify basic load balancer configuration is a supported scenario

    ## verify scenario for a single load balancer
    Write-Progress -Activity "Validating Migration Scenario" -Status "Validating Migration Scenario" -PercentComplete 0 -Id 2
    If ($PSCmdlet.ParameterSetName -ne 'MultiLB') {
        if ($PSBoundParameters.ContainsKey("StandardLoadBalancerName")) {
            $StdLoadBalancerName = $StandardLoadBalancerName
        }
        else {
            $StdLoadBalancerName = $BasicLoadBalancer.Name
        }

        $scenario = Test-SupportedMigrationScenario -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancerName -Force:($force.IsPresent -or $validateScenarioOnly.isPresent) -Pre:$Pre.IsPresent -basicLBBackendIds $BasicLoadBalancer.BackendAddressPools.Id

        # create a migration config object array with a single entry
        $migrationConfigs = @(@{
                BasicLoadBalancer        = $BasicLoadBalancer
                StandardLoadBalancerName = $StdLoadBalancerName
                scenario                 = $scenario
                vmssRefObject            = ''
            })
        
        if ($validateScenarioOnly) {
            log -Message "[Start-AzBasicLoadBalancerUpgrade] Scenario validation completed, exiting because -validateScenarioOnly was specified"
            break
        }
    }
    ## verify scenario for multiple load balancers
    ElseIf ($PSCmdlet.ParameterSetName -eq 'MultiLB') {
        log -Message "[Start-AzBasicLoadBalancerUpgrade] -MultiLBConfig parameter set detected, validating scenarios for multiple load balancers"

        # verify scenario for each load balancer in the multiLBConfig array
        ForEach ($LBConfig in $multiLBConfig) {
            
            # set standard LB name if none is specified
            if (![string]::IsNullOrEmpty($LBConfig.standardLoadBalancerName)) {
                $StdLoadBalancerName = $LBConfig.standardLoadBalancerName
            }
            else {
                $LBConfig.standardLoadBalancerName = $LBConfig.basicLoadBalancer.Name
                $StdLoadBalancerName = $LBConfig.basicLoadBalancer.Name
            }

            $BasicLoadBalancer = $LBConfig.basicLoadBalancer

            log -Message "[Start-AzBasicLoadBalancerUpgrade] Validating scenario for Basic Load Balancer '$($BasicLoadBalancer.Name)' in Resource Group '$($basicLoadBalancer.ResourceGroupName)'"
            $scenario = Test-SupportedMigrationScenario -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancerName -Force:($force.IsPresent -or $validateScenarioOnly.isPresent) -Pre:$Pre.IsPresent -basicLBBackendIds $multiLBConfig.BasicLoadBalancer.BackendAddressPools.Id

            # add the evaluated scenario details to the LBConfig object
            $LBConfig['scenario'] = $scenario
        }

        # verify the scenario for multi-load balancer configurations
        Test-SupportedMultiLBScenario -MultiLBConfig $multiLBConfig
        
        if ($validateScenarioOnly) {
            log -Message "[Start-AzBasicLoadBalancerUpgrade] Scenario validation completed, exiting because -validateScenarioOnly was specified"
            break
        }

        # create a migration config object array from the input multiLBConfig parameter object array
        $migrationConfigs = $multiLBConfig
    }
    Write-Progress -Activity "Validating Migration Scenario" -Status "Validating Migration Scenario" -Completed -Id 2

    # prepare for migration by backing up the basic LB, upgrading Public IPs, and deleting the LB
    # this is done before the migration starts to ensure that all basic LBs are disassociated with any backend pool members, avoiding a mixed SKU scenario which would otherwise occur
    
    Write-Progress -Activity "Preparing for Migration" -Status "Preparing for Migration" -Id 3 -PercentComplete 0
    log -Message "[Start-AzBasicLoadBalancerUpgrade] Preparing for migration by backing up and deleteing the basic LB(s)"
    $migrationConfigs = LBMigrationPrep -migrationConfigs $migrationConfigs -RecoveryBackupPath $RecoveryBackupPath
    Write-Progress -Activity "Preparing for Migration" -Status "Preparing for Migration" -Completed -Id 3

    # initiate the migration of each load balancer in the migration config array
    Write-Progress -Activity "Starting Migration" -Status "Starting Migration" -Id 4
    $migrationConfigsCompleted = 0
    ForEach ($migrationConfig in $migrationConfigs) {
        Write-Progress -Activity "Starting Migration" -Status "Starting migration of basic load balancer '$($migrationConfig.BasicLoadBalancer.Name)'" -Id 4 -PercentComplete 0
        log -Message "[Start-AzBasicLoadBalancerUpgrade] Starting migration for Basic Load Balancer '$($migrationConfig.BasicLoadBalancer.Name)' in Resource Group '$($migrationConfig.BasicLoadBalancer.ResourceGroupName)'"

        $standardScenarioParams = @{
            BasicLoadBalancer             = $migrationConfig.BasicLoadBalancer
            StandardLoadBalancerName      = $migrationConfig.StandardLoadBalancerName
            Scenario                      = $migrationConfig.scenario
            outputMigrationValiationObj   = $outputMigrationValiationObj.IsPresent
            skipUpgradeNATPoolsToNATRules = $skipUpgradeNATPoolsToNATRules.IsPresent
        }

        switch ($migrationConfig.scenario.BackendType) {
            'VM' {
                switch ($migrationConfig.scenario.ExternalOrInternal) {
                    'internal' {
                        if ((!$PSBoundParameters.ContainsKey("FailedMigrationRetryFilePathLB"))) {
                            InternalLBMigrationVM @standardScenarioParams -RecoveryBackupPath $RecoveryBackupPath
                        }
                        else {
                            RestoreInternalLBMigrationVM @standardScenarioParams
                        }
                    }
                    'external' {
                        if ((!$PSBoundParameters.ContainsKey("FailedMigrationRetryFilePathLB"))) {
                            PublicLBMigrationVM @standardScenarioParams -RecoveryBackupPath $RecoveryBackupPath
                        }
                        else {
                            RestoreExternalLBMigrationVM @standardScenarioParams
                        }
                    }
                }
            }
            'VMSS' {
                switch ($migrationConfig.scenario.ExternalOrInternal) {
                    'internal' {
                        if ((!$PSBoundParameters.ContainsKey("FailedMigrationRetryFilePathLB"))) {
                            InternalLBMigrationVmss @standardScenarioParams -RecoveryBackupPath $RecoveryBackupPath -refVmss $migrationConfig.vmssRefObject
                        }
                        else {
                            RestoreInternalLBMigrationVmss @standardScenarioParams -vmss $vmss
                        }
                    }
                    'external' {
                        if ((!$PSBoundParameters.ContainsKey("FailedMigrationRetryFilePathLB"))) {
                            PublicLBMigrationVmss @standardScenarioParams -RecoveryBackupPath $RecoveryBackupPath -refVmss $migrationConfig.vmssRefObject
                        }
                        else {
                            RestoreExternalLBMigrationVmss @standardScenarioParams -vmss $vmss
                        }
                    }
                }
            }
            'Empty' {
                switch ($migrationConfig.scenario.ExternalOrInternal) {
                    'internal' {
                        if ((!$PSBoundParameters.ContainsKey("FailedMigrationRetryFilePathLB"))) {
                            InternalLBMigrationEmpty @standardScenarioParams -RecoveryBackupPath $RecoveryBackupPath
                        }
                        else {
                            RestoreInternalLBMigrationEmpty @standardScenarioParams
                        }
                    }
                    'external' {
                        if ((!$PSBoundParameters.ContainsKey("FailedMigrationRetryFilePathLB"))) {
                            PublicLBMigrationEmpty @standardScenarioParams -RecoveryBackupPath $RecoveryBackupPath
                        }
                        else {
                            RestoreExternalLBMigrationEmpty @standardScenarioParams
                        }
                    }
                }
            }
        }

        $migrationConfigsCompleted++
        $completedPercent = ($migrationConfigsCompleted / $migrationConfigs.Count) * 100
        Write-Progress -Activity "Completed migration" -Status "Completed migration of basic load balancer '$($migrationConfig.BasicLoadBalancer.Name)'" -PercentComplete $completedPercent -Id 4
    }

    log -Message "############################## Migration Completed ##############################"

    $global:FollowLog = $null
}

Export-ModuleMember -Function Start-AzBasicLoadBalancerUpgrade
