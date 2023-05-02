Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")

function Update-Vmss {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $vmss
    )
    log -Message "[UpdateVmss] Updating configuration of VMSS '$($vmss.Name)'"

    $job = Update-AzVmss -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name -VirtualMachineScaleSet $vmss -AsJob

    While ($job.State -eq 'Running') {
        Start-Sleep -Seconds 15
        log -Message "[UpdateVmss] Waiting for job (id: '$($job.id)') updating VMSS '$($vmss.name)' to complete..."
    }

    If ($job.Error -or $job.State -eq 'Failed') {
        Write-Error "An error occured while updating the VMSS: $($job | Receive-Job -Keep | Out-String)" -ErrorAction Stop
    }

    log -Message "[UpdateVmss] Completed update configuration of VMSS '$($vmss.Name)'"
}

Export-ModuleMember -Function Update-Vmss
