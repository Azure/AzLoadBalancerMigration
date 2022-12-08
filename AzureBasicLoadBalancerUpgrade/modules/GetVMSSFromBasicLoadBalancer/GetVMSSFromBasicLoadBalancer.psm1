# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")
function GetVMSSFromBasicLoadBalancer {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer
    )
    log -Message "[GetVMSSFromBasicLoadBalancer] Initiating GetVMSSFromBasicLoadBalancer"

    try {
        $ErrorActionPreference = 'Stop'
        $vmssId = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object { ($_ -split '/virtualMachines/')[0] } | Select-Object -Unique

        log -Message "[GetVMSSFromBasicLoadBalancer] Getting VMSS object '$vmssId' from Azure"
        $vmss = Get-AzResource -ResourceId $vmssId | Get-AzVmss
    }
    catch {
        $message = @"
        [GetVMSSFromBasicLoadBalancer] An error occured when getting VMSS '$($vmss.Name)' in resource group '$($vmss.ResourceGroupName)'. To recover
        address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup
        State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
        log 'Error' $message -terminateOnError
    }
    log -Message "[GetVMSSFromBasicLoadBalancer] VMSS loaded Name $($vmss.Name) from RG $($vmss.ResourceGroupName)"
    return , $vmss
}

Export-ModuleMember -Function GetVMSSFromBasicLoadBalancer