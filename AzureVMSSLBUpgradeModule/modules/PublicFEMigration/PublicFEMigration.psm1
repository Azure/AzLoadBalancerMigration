# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")
function PublicFEMigration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[PublicFEMigration] Initiating Public Frontend Migration"
    $basicLoadBalancerFeConfig = $BasicLoadBalancer.FrontendIpConfigurations

    # Change allocation method to staic and SKU to Standard
    foreach ($feConfig in $basicLoadBalancerFeConfig) {
        $pip = Get-AzPublicIpAddress -ResourceGroupName $feConfig.PublicIpAddress.Id.Split('/')[4] -Name $feConfig.PublicIpAddress.Id.Split('/')[-1]
        if ($pip.PublicIpAllocationMethod -ne "Static" -or $pip.Sku.Name -ne "Standard") {
            log -Message "[PublicFEMigration] '$($pip.Name)' ('$($pip.IpAddress)') was using Dynamic IP or Basic SKU, changing to Static IP allocation method and Standard SKU." -Severity "Warning"
            $pip.PublicIpAllocationMethod = "Static"
            $pip.Sku.Name = "Standard"

            try {
                $ErrorActionPreference = 'Stop'
                $upgradedPip = Set-AzPublicIpAddress -PublicIpAddress $pip
            }
            catch {
                $message = @"
                [PublicFEMigration] An error occured when upgrading public IP '$($pip.Name)' from Basic to Standard SKU. To recover 
                address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load 
                Balancer backup State file located either in this directory or the directory specified with -RecoveryBackupPath. 
                `nError message: $_
"@
                log 'Error' $message
                Exit
            }

            log -Message "[PublicFEMigration] Completed the migration of '$($pip.Name)' ('$($upgradedPip.IpAddress)') from Basic SKU and/or dynamic to static" -Severity "Information"
        }
        
        try {
            $ErrorActionPreference = 'Stop'
            $StdLoadBalancer | Add-AzLoadBalancerFrontendIpConfig -Name $feConfig.Name -PublicIpAddressId $pip.Id > $null
        }
        catch {
            $message = @"
            [PublicFEMigration] An error occured when adding the public front end '$($feConfig.Name)' to the new Standard LB. To recover 
            address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load 
            Balancer backup State file located either in this directory or the directory specified with -RecoveryBackupPath. 
            `nError message: $_
"@
            log 'Error' $message
            Exit
        }
    }
    log -Message "[PublicFEMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"

    try {
        $ErrorActionPreference = 'Stop'
        Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer > $null
    }
    catch {
        $message = @"
        [PublicFEMigration] An error occured when moving Public IPs to the new Standard Load Balancer. To recover 
        address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic 
        Load Balancer backup State file located either in this directory or the directory specified with -RecoveryBackupPath.
         `nError message: $_
"@
        log 'Error' $message
        Exit
    }

    log -Message "[PublicFEMigration] Public Frontend Migration Completed"
}

Export-ModuleMember -Function PublicFEMigration