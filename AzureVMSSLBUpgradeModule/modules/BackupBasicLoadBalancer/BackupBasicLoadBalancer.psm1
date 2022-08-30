# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
function BackupBasicLoadBalancer {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer
    )
    log -Message "[BackupBasicLoadBalancer] Initiating Backup of Basic Load Balancer Configurations"
    $backupDateTime = Get-Date -Format FileDateTime
    #############################
    # ToDo: We need to check if there are any other type of backend pools and if so, stop the execution and log the error
    #############################
    $outputFileName = ('State-' + $BasicLoadBalancer.Name + "-" + $BasicLoadBalancer.ResourceGroupName + "-" + $backupDateTime + ".json")
    ConvertTo-Json -Depth 100 $BasicLoadBalancer | Out-File -FilePath $outputFileName 
    log -Message "[BackupBasicLoadBalancer] JSON backup Basic Load Balancer to file $outputFileName Completed"
    
    try {
        Export-AzResourceGroup -ResourceGroupName $BasicLoadBalancer.ResourceGroupName -Resource $BasicLoadBalancer.Id -SkipAllParameterization -ErrorAction Stop > $null
    }
    catch {
        $message = "[BackupBasicLoadBalancer] An error occured while exporting the basic load balancer '$($BasicLoadBalancer.Name)' to an ARM template for backup purposes. Error: $_"
        log -Severity Error -Message $message
        Exit
    }

    $newExportedResourceFileName = ("ARMTemplate-" + $BasicLoadBalancer.Name + "-" + $BasicLoadBalancer.ResourceGroupName + '-' + $backupDateTime + ".json")
    Move-Item ($BasicLoadBalancer.ResourceGroupName + ".json") $newExportedResourceFileName
    log -Message "[BackupBasicLoadBalancer] ARM Template Backup Basic Load Balancer to file $($newExportedResourceFileName) Completed"
    log -Message "[BackupBasicLoadBalancer] End Backup of Basic Load Balancer Configurations"
}
Export-ModuleMember -Function BackupBasicLoadBalancer