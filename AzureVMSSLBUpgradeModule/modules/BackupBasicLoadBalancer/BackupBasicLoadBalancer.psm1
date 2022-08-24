# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
function BackupBasicLoadBalancer {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer
    )
    log -Message "[BackupBasicLoadBalancer] Initiating Backup of Basic Load Balancer Configurations"
    ConvertTo-Json -Depth 100 $BasicLoadBalancer | Out-File -FilePath ($BasicLoadBalancer.Name + "-" + (Get-Date -Format FileDateTime) + ".json")
    Export-AzResourceGroup -ResourceGroupName $BasicLoadBalancer.ResourceGroupName -Resource $BasicLoadBalancer.Id -SkipAllParameterization  | Out-Null
    Move-Item ($BasicLoadBalancer.ResourceGroupName + ".json") ($BasicLoadBalancer.ResourceGroupName + "-" + (Get-Date -Format FileDateTime) + ".json")
    log -Message "[BackupBasicLoadBalancer] End Backup of Basic Load Balancer Configurations"
}
Export-ModuleMember -Function BackupBasicLoadBalancer