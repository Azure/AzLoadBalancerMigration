# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
function UpdateVmssInstances {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $vmss
    )
    log -Message "[UpdateVmssInstances] Initiating Update Vmss Instances"

    If ($vmss.UpgradePolicy.Mode -ne 'Manual') {
        $message = "[UpdateVmssInstances] VMSS '$($vmss.Id)' is configued with UpgradePolicy '$($vmss.UpgradePolicy.Mode)', which is not supported by this script"
        log 'Error' $message
        Exit
    }

    log -Message "[UpdateVmssInstances] Updating VMSS Instances. This process may take a while depending of how many instances."
    $vmssIntances = Get-AzVmssVM -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name
    foreach ($vmssInstance in $vmssIntances) {
        log -Message "[UpdateVmssInstances] Updating VMSS Instance $($vmssInstance.Name)"
        Update-AzVmssInstance -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name -InstanceId $vmssInstance.InstanceId > $null
    }

    log -Message "[UpdateVmssInstances] Update Vmss Instances Completed"
}

Export-ModuleMember -Function UpdateVmssInstances

