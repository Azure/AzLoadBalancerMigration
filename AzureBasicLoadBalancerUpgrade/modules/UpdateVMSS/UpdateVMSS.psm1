Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")

function UpdateVmss {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet] $vmss
    )
    log -Message "[UpdateVmss] Saving VMSS $($vmss.Name)"
    try {
        $ErrorActionPreference = 'Stop'
        Update-AzVmss -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name -VirtualMachineScaleSet $vmss > $null
    }
    catch {
        $exceptionType = (($_.Exception.Message -split 'ErrorCode:')[1] -split 'ErrorMessage:')[0].Trim()
        if($exceptionType -eq "MaxUnhealthyInstancePercentExceededBeforeRollingUpgrade"){
            $message = @"
            [UpdateVmss] An error occured when attempting to update VMSS upgrade policy back to $($vmss.UpgradePolicy.Mode).
            Looks like some instances were not healthy and in orther to change the VMSS upgra policy the majority of instances
            must be healthy according to the upgrade policy. The module will continue but it will be required to change the VMSS
            Upgrade Policy manually. `nError message: $_
"@
            log 'Error' $message
        }
        else {
            $message = @"
            [UpdateVmss] An error occured when attempting to update VMSS network config new Standard
            LB backend pool membership. To recover address the following error, and try again specifying the
            -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup State file located either in
            this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
            log 'Error' $message -terminateOnError
        }
    }
}

Export-ModuleMember -Function .\UpdateVMSS.psd1