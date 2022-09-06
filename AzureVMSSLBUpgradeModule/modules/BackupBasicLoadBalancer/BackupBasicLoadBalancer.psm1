# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
function BackupBasicLoadBalancer {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer
    )
    log -Message "[BackupBasicLoadBalancer] Initiating Backup of Basic Load Balancer Configurations"
    try {
        $ErrorActionPreference = 'Stop'

        $backupDateTime = Get-Date -Format FileDateTime
        $outputFileName = ('State-' + $BasicLoadBalancer.Name + "-" + $BasicLoadBalancer.ResourceGroupName + "-" + $backupDateTime + ".json")
        ConvertTo-Json -Depth 100 $BasicLoadBalancer | Out-File -FilePath $outputFileName
        log -Message "[BackupBasicLoadBalancer] JSON backup Basic Load Balancer to file $outputFileName Completed"

        Export-AzResourceGroup -ResourceGroupName $BasicLoadBalancer.ResourceGroupName -Resource $BasicLoadBalancer.Id -SkipAllParameterization > $null
        $newExportedResourceFileName = ("ARMTemplate-" + $BasicLoadBalancer.Name + "-" + $BasicLoadBalancer.ResourceGroupName + '-' + $backupDateTime + ".json")
        Move-Item ($BasicLoadBalancer.ResourceGroupName + ".json") $newExportedResourceFileName
    }
    catch {
        $message = "[BackupBasicLoadBalancer] An error occured while exporting the basic load balancer '$($BasicLoadBalancer.Name)' to an ARM template for backup purposes. Error: $_"
        log -Severity Error -Message $message
        Exit
    }
    log -Message "[BackupBasicLoadBalancer] ARM Template Backup Basic Load Balancer to file $($newExportedResourceFileName) Completed"
}
Export-ModuleMember -Function BackupBasicLoadBalancer