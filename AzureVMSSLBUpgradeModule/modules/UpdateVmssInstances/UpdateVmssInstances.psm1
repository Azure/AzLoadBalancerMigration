# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
function UpdateVmssInstances {
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
        log -Message "[UpdateVmssInstances] Updating VMSS Instances. This process may take a while depending of how many instances."
        $vmssIntances = Get-AzVmssVM -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name
        foreach ($vmssInstance in $vmssIntances) {
            log -Message "[UpdateVmssInstances] Updating VMSS Instance $($vmssInstance.Name)"
            try {
                Update-AzVmssInstance -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name -InstanceId $vmssInstance.InstanceId > $null
            }
            catch {
                log -Message "[UpdateVmssInstances] Fail to update VMSS Instance $($vmssInstance.Name). This instance must be updated manually. Error: $_" -Severity "Warning"
            }
        }
    }
    Else {
        # ###### TO-DO ######
        # *** Either use a Sleep or other method of ensuring the change has been applied to all instance before attempting to add the VMSS to the Standard LB!
        # #######################

        log -Message "[UpdateVmssInstances] VMSS '$($vmss.Name)' is configured with Upgrade Policy '$($vmss.UpgradePolicy.Mode)', so the update NetworkProfile will be applied automatically."
    }
    log -Message "[UpdateVmssInstances] Update Vmss Instances Completed"
}

Export-ModuleMember -Function UpdateVmssInstances

