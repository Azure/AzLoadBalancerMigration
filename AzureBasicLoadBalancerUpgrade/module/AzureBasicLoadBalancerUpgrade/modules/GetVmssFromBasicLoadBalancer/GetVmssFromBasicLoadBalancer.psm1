# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")
function GetVmssFromBasicLoadBalancer {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer
    )
    log -Message "[GetVmssFromBasicLoadBalancer] Initiating GetVmssFromBasicLoadBalancer"

    try {
        $ErrorActionPreference = 'Stop'

        # check backend pools and nat rules for vmssids
        $vmssId = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id + $BasicLoadBalancer.inboundNatRules.BackendIpConfiguration.id | Foreach-Object { 
            If (![string]::IsNullOrEmpty($_)) {
                ($_ -split '/virtualMachines/')[0].ToLower() }
        } | Select-Object -Unique

        log -Message "[GetVmssFromBasicLoadBalancer] Getting VMSS object '$vmssId' from Azure"
        $vmss = Get-AzResource -ResourceId $vmssId | Get-AzVmss
    }
    catch {
        $message = "[GetVmssFromBasicLoadBalancer] An error occured when getting VMSS '$($vmss.Name)' in resource group '$($vmss.ResourceGroupName)'. To recover, address the cause of the following error, then follow the steps at https://aka.ms/basiclbupgradefailure to retry the migration. Error: $_"
        log 'Error' $message -terminateOnError
    }
    log -Message "[GetVmssFromBasicLoadBalancer] VMSS loaded Name $($vmss.Name) from RG $($vmss.ResourceGroupName)"
    return , $vmss
}

Export-ModuleMember -Function GetVmssFromBasicLoadBalancer
