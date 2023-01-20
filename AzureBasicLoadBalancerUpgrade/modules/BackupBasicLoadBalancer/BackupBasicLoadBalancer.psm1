# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")

function RestoreLoadBalancer {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][string] $BasicLoadBalancerJsonFile
    )
    log -Message "[RestoreLoadBalancer] Initiating Restore Load Balancer from JSON Backup"

    if (!(Test-Path $BasicLoadBalancerJsonFile)) {
        log -Severity "Error" -Message "[RestoreLoadBalancer] Unable to load the file $BasicLoadBalancerJsonFile. File not found or missing permission." -terminateOnError
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
        log -Severity Error -Message $message -terminateOnError
    }
}

function RestoreVMSS {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][string] $VMSSJsonFile
    )
    log -Message "[RestoreVMSS] Initiating Restore VMSS from JSON Backup"

    if (!(Test-Path $VMSSJsonFile)) {
        log -Severity "Error" -Message "[RestoreVMSS] Unable to load the file $VMSSJsonFile. File not found or missing permission." -terminateOnError
    }
    log -Message "[RestoreVMSS] Loading file $VMSSJsonFile"
    $VMSSJson = Get-Content $VMSSJsonFile
    try {
        $ErrorActionPreference = 'Stop'
        log -Message "[RestoreVMSS] Deserializing backup to a object type [Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet]"
        $vmss = [System.Text.Json.JsonSerializer]::Deserialize($VMSSJson, [Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet])
        log -Message "[RestoreVMSS] Deserialization Completed"
        return $vmss
    }
    catch {
        $message = "[RestoreVMSS] An error occured while deserializing backup from JSON File. Error: $_"
        log -Severity Error -Message $message -terminateOnError
    }
}

function BackupBasicLoadBalancer {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $true)] $RecoveryBackupPath
    )
    log -Message "[BackupBasicLoadBalancer] Initiating Backup of Basic Load Balancer Configurations to path '$RecoveryBackupPath'"
    try {
        $ErrorActionPreference = 'Stop'

        $backupDateTime = Get-Date -Format FileDateTime

        # export serialized JSON object of Basic LB for automated recovery scenarios
        $outputFileName = ('State_' + $BasicLoadBalancer.Name + "_" + $BasicLoadBalancer.ResourceGroupName + "_" + $backupDateTime + ".json")
        $outputFilePath = Join-Path -Path $RecoveryBackupPath -ChildPath $outputFileName

        $options = [System.Text.Json.JsonSerializerOptions]::new()
        $options.WriteIndented = $true
        #$options.IgnoreReadOnlyFields = $true # This is only available in PS 7
        $options.IgnoreReadOnlyProperties = $true
        [System.Text.Json.JsonSerializer]::Serialize($BasicLoadBalancer, [Microsoft.Azure.Commands.Network.Models.PSLoadBalancer], $options) | Out-File -FilePath $outputFilePath
        log -Message "[BackupBasicLoadBalancer] JSON backup Basic Load Balancer to file $outputFilePath Completed"

        # export ARM template of Basic LB for manual recovery scenarios
        log -Message "[BackupBasicLoadBalancer] Exporting Basic Load Balancer ARM template to path '$RecoveryBackupPath'..."
        Export-AzResourceGroup -ResourceGroupName $BasicLoadBalancer.ResourceGroupName -Resource $BasicLoadBalancer.Id -SkipAllParameterization -Path $RecoveryBackupPath -Force > $null
        $newExportedResourceFileName = ("ARMTemplate_" + $BasicLoadBalancer.Name + "_" + $BasicLoadBalancer.ResourceGroupName + '_' + $backupDateTime + ".json")
        $exportedResourceFilePath = Join-Path -Path $RecoveryBackupPath -ChildPath ($BasicLoadBalancer.ResourceGroupName + ".json")
        $exportedTemplate = Rename-Item -Path $exportedResourceFilePath -NewName $newExportedResourceFileName -PassThru
        log -Message "[BackupBasicLoadBalancer] Completed export Basic Load Balancer ARM template to path '$($exportedTemplate.FullName)'..."

    }
    catch {
        $message = "[BackupBasicLoadBalancer] An error occured while exporting the basic load balancer '$($BasicLoadBalancer.Name)' to an ARM template for backup purposes. Error: $_"
        log -Severity Error -Message $message -terminateOnError
    }

    # Backup VMSS Object
    $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object { (($_ -split '/virtualMachines/')[0]).ToLower() } | Select-Object -Unique
    foreach ($vmssId in $vmssIds) {
        $message = "[BackupBasicLoadBalancer] Attempting to create a file-based backup VMSS with id '$vmssId'"
        log -Severity Information -Message $message

        try {
            $ErrorActionPreference = 'Stop'
            $vmss = Get-AzResource -ResourceId $vmssId | Get-AzVmss
            $outputFileNameVMSS = ('VMSS_' + $vmss.Name + "_" + $vmss.ResourceGroupName + "_" + $backupDateTime + ".json")
            $outputFilePathVSS = Join-Path -Path $RecoveryBackupPath -ChildPath $outputFileNameVMSS

            [System.Text.Json.JsonSerializer]::Serialize($vmss, [Microsoft.Azure.Commands.Compute.Automation.Models.PSVirtualMachineScaleSet], $options) | Out-File -FilePath $outputFilePathVSS
        }
        catch {
            $message = "[BackupBasicLoadBalancer] An error occured while exporting the VMSS '$($vmssName)' for backup purposes. Error: $_"
            log -Severity Error -Message $message -terminateOnError
        }
    }

}
Export-ModuleMember -Function BackupBasicLoadBalancer
Export-ModuleMember -Function RestoreLoadBalancer
Export-ModuleMember -Function RestoreVMSS