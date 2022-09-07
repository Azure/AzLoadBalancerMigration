# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")

function RestoreLoadBalancer {
    param (
        [Parameter(Mandatory = $True)][string] $BasicLoadBalancerJsonFile
    )
    log -Message "[RestoreLoadBalancer] Initiating Restore Load Balancer from JSON Backup"

    if (!(Test-Path $BasicLoadBalancerJsonFile)) {
        log -Severity "Error" -Message "[RestoreLoadBalancer] Unable to load the file $BasicLoadBalancerJsonFile. File not found or missing permission."
        Exit
    }
    log -Message "[RestoreLoadBalancer] Loading file $BasicLoadBalancerJsonFile"
    $BasicLoadBalancerJson = Get-Content $BasicLoadBalancerJsonFile
    try {
        $ErrorActionPreference = 'Stop'
        log -Message "[RestoreLoadBalancer] Deserializing backup to a object type [Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]"
        $BasicLoadBalancer = [System.Text.Json.JsonSerializer]::Deserialize($BasicLoadBalancerJson, [Microsoft.Azure.Commands.Network.Models.PSLoadBalancer])
        log -Message "[RestoreLoadBalancer] Deserialization Completed"
        return $BasicLoadBalancer
    }
    catch {
        $message = "[RestoreLoadBalancer] An error occured while deserializing backup from JSON File. Error: $_"
        log -Severity Error -Message $message
        Exit
    }
}

function BackupBasicLoadBalancer {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer
    )
    log -Message "[BackupBasicLoadBalancer] Initiating Backup of Basic Load Balancer Configurations"
    try {
        $ErrorActionPreference = 'Stop'

        $backupDateTime = Get-Date -Format FileDateTime
        $outputFileName = ('State-' + $BasicLoadBalancer.Name + "-" + $BasicLoadBalancer.ResourceGroupName + "-" + $backupDateTime + ".json")
        #ConvertTo-Json -Depth 100 $BasicLoadBalancer | Out-File -FilePath $outputFileName

        $options = [System.Text.Json.JsonSerializerOptions]::new()
        $options.WriteIndented = $true
        #$options.IgnoreReadOnlyFields = $true # This is only available in PS 7
        $options.IgnoreReadOnlyProperties = $true
        [System.Text.Json.JsonSerializer]::Serialize($BasicLoadBalancer,[Microsoft.Azure.Commands.Network.Models.PSLoadBalancer],$options) | Out-File -FilePath $outputFileName
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

    # Backup VMSS Object
    $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object{$_.split("virtualMachines")[0]} | Select-Object -Unique
    foreach ($vmssId in $vmssIds) {
        $vmssName = $vmssId.split("/")[8]
        $vmssRg = $vmssId.Split('/')[4]
        try {
            $ErrorActionPreference = 'Stop'
            $vmss = Get-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName
            $outputFileNameVMSS = ('VMSS-' + $vmss.Name + "-" + $vmss.ResourceGroupName + "-" + $backupDateTime + ".json")
            [System.Text.Json.JsonSerializer]::Serialize($vmss,[Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet],$options) | Out-File -FilePath $outputFileNameVMSS
        }
        catch {
            $message = "[BackupBasicLoadBalancer] An error occured while exporting the VMSS '$($vmssName)' for backup purposes. Error: $_"
            log -Severity Error -Message $message
            Exit
        }
    }
    log -Message "[BackupBasicLoadBalancer] ARM Template Backup Basic Load Balancer to file $($newExportedResourceFileName) Completed"
}
Export-ModuleMember -Function BackupBasicLoadBalancer
Export-ModuleMember -Function RestoreLoadBalancer