# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
function BackupBasicLoadBalancer {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer
    )
    log -Message "[BackupBasicLoadBalancer] Initiating Backup of Basic Load Balancer Configurations"
    $backupDateTime = Get-Date -Format FileDateTime

    # Detecting if there are any backend pools that is not virtualMachineScaleSets, if so, exit
    log -Message "[BackupBasicLoadBalancer] Checking if there are any backend pools that is not virtualMachineScaleSets"
    foreach ($backendAddressPool in $BasicLoadBalancer.BackendAddressPools) {
        foreach ($backendIpConfiguration in $backendAddressPool.BackendIpConfigurations) {
            if ($backendIpConfiguration.Id.split("/")[7] -ne "virtualMachineScaleSets") {
                log -Message "[BackupBasicLoadBalancer] Basic Load Balancer has backend pools that is not virtualMachineScaleSets, exiting" -Severity "Error"
                exit
            }
        }
    }
    log -Message "[BackupBasicLoadBalancer] All backend pools are virtualMachineScaleSets!"

    ConvertTo-Json -Depth 100 $BasicLoadBalancer | Out-File -FilePath ($BasicLoadBalancer.Name + "-" + $backupDateTime + ".json")
    log -Message "[BackupBasicLoadBalancer] JSON backup Basic Load Balancer $($BasicLoadBalancer.Name + "-" + $backupDateTime + ".json") Completed"
    Export-AzResourceGroup -ResourceGroupName $BasicLoadBalancer.ResourceGroupName -Resource $BasicLoadBalancer.Id -SkipAllParameterization > $null
    Move-Item ($BasicLoadBalancer.ResourceGroupName + ".json") ("ARM-" + $BasicLoadBalancer.Name + "-" + $backupDateTime + ".json")
    log -Message "[BackupBasicLoadBalancer] ARM Template Backup Basic Load Balancer $("ARM-" + $BasicLoadBalancer.Name + "-" + $backupDateTime + ".json") Completed"
    log -Message "[BackupBasicLoadBalancer] End Backup of Basic Load Balancer Configurations"
}
Export-ModuleMember -Function BackupBasicLoadBalancer