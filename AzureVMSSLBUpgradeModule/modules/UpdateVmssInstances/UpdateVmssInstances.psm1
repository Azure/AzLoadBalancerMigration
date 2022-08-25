# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
function UpdateVmssInstances {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $vmss
    )
    log -Message "[UpdateVmssInstances] Initiating Update Vmss Instances"

    log -Message "[UpdateVmssInstances] Updating VMSS Instances"
    $vmssIntances = Get-AzVmssVM -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name
    foreach ($vmssInstance in $vmssIntances) {
        log -Message "[UpdateVmssInstances] Updating VMSS Instance $($vmssInstance.Name)"
        Update-AzVmssInstance -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name -InstanceId $vmssInstance.InstanceId
    }

    log -Message "[UpdateVmssInstances] Update Vmss Instances Completed"
}

Export-ModuleMember -Function UpdateVmssInstances

