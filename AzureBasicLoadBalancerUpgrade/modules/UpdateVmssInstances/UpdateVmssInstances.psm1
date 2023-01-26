# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")
function UpdateVmssInstances {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $vmss
    )
    log -Message "[UpdateVmssInstances] Initiating Update Vmss Instances"

    # If ($vmss.UpgradePolicy.Mode -ne 'Manual') {
    #     $message = "[UpdateVmssInstances] VMSS '$($vmss.Id)' is configued with UpgradePolicy '$($vmss.UpgradePolicy.Mode)', which is not supported by this script"
    #     log 'Error' $message
    #     Exit
    # }

    If ($vmss.UpgradePolicy.Mode -eq 'Manual') {
        log -Message "[UpdateVmssInstances] VMSS '$($vmss.Name)' is configured with Upgrade Policy '$($vmss.UpgradePolicy.Mode)', so each VMSS instance will have the network profile updated."
        log -Message "[UpdateVmssInstances] Updating VMSS Instances..."

        $vmssInstances = Get-AzVmssVM -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name

        try {
            $ErrorActionPreference = 'Stop'
            $updateJob = Update-AzVmssInstance -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name -InstanceId $vmssInstances.InstanceId -AsJob

            log -Message "[UpdateVmssInstances] Waiting for VMSS instance update job to complete..."
            $updateJob | Wait-Job | Out-Null
        }
        catch {
            $message = @"
            An error occured when initiating the 'Update-AzVMssInstance' job on all instances in VMSS '$($vmss.Name)'. To recover, 
            address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup 
            State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@  
            log 'Error' $message -terminateOnError
        }
        finally {
            If (![string]::IsNullorEmpty($updateJob.Error)) {
                $message = @"
                An error occured while executing the 'Update-AzVMssInstance' job on all instances in VMSS '$($vmss.Name)'. To recover, 
                address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup 
                State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $($updateJob.Error)
"@  
                log 'Error' $message -terminateOnError
            }
        }

    }
    Else {
        log -Message "[UpdateVmssInstances] VMSS '$($vmss.Name)' is configured with Upgrade Policy '$($vmss.UpgradePolicy.Mode)', so the update NetworkProfile will be applied automatically."
    }
    log -Message "[UpdateVmssInstances] Update Vmss Instances Completed"
}

Export-ModuleMember -Function UpdateVmssInstances

