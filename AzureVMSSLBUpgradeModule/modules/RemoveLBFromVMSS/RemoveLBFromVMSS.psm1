
# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
function RemoveLBFromVMSS {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $VMSS,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer
    )
    log -Message "[RemoveLBFromVMSS] Initiating removal of LB $($BasicLoadBalancer.Name) from VMSS $($VMSS.Name)"

    Remove-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $BasicLoadBalancerName -Force
    log -Message "[PublicFEMigration] Removal of LB $($BasicLoadBalancer.Name) from VMSS $($VMSS.Name) Completed"
}

Export-ModuleMember -Function PublicFEMigration