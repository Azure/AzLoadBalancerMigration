# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")
function PublicIPToStatic {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer
    )
    log -Message "[LBPublicIPToStatic] Changing public IP addresses to static (if necessary)"
    $basicLoadBalancerFeConfig = $BasicLoadBalancer.FrontendIpConfigurations

    # Change allocation method to staic and SKU to Standard
    foreach ($feConfig in $basicLoadBalancerFeConfig) {
        $pip = Get-AzPublicIpAddress -ResourceGroupName $feConfig.PublicIpAddress.Id.Split('/')[4] -Name $feConfig.PublicIpAddress.Id.Split('/')[-1]
        if ($pip.PublicIpAllocationMethod -ne "Static") {
            log -Message "[LBPublicIPToStatic] '$($pip.Name)' ('$($pip.IpAddress)') was using Dynamic IP, changing to Static IP allocation method." -Severity "Information"
            $pip.PublicIpAllocationMethod = "Static"

            try {
                $ErrorActionPreference = 'Stop'
                $upgradedPip = Set-AzPublicIpAddress -PublicIpAddress $pip
            }
            catch {
                $message = "[LBPublicIPToStatic] An error occured when changing public IP '$($pip.Name)' from dyanamic to standard. To recover address the following error, then follow the steps at https://aka.ms/basiclbupgradefailure to retry the migration. `nError message: $_"
                log 'Error' $message -terminateOnError
            }

            log -Message "[LBPublicIPToStatic] Completed the migration of '$($pip.Name)' ('$($upgradedPip.IpAddress)') from Basic SKU and/or dynamic to static" -Severity "Information"
        }
    }

    log -Message "[LBPublicIPToStatic] Public Frontend Migration Completed"
}
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
        if ($pip.Sku.Name -ne "Standard") {
            log -Message "[PublicFEMigration] '$($pip.Name)' ('$($pip.IpAddress)') is using Basic SKU, changing Standard SKU." -Severity "Information"
            $pip.Sku.Name = "Standard"

            try {
                $ErrorActionPreference = 'Stop'
                $upgradedPip = Set-AzPublicIpAddress -PublicIpAddress $pip
            }
            catch {
                $message = "[PublicFEMigration] An error occured when upgrading public IP '$($pip.Name)' from Basic to Standard SKU. To recover address the following error, then follow the steps at https://aka.ms/basiclbupgradefailure to retry the migration. `nError message: $_"
                log 'Error' $message -terminateOnError
            }

            log -Message "[PublicFEMigration] Completed the migration of '$($pip.Name)' ('$($upgradedPip.IpAddress)') from Basic SKU and/or dynamic to static" -Severity "Information"
        }
        
        try {
            $ErrorActionPreference = 'Stop'
            $StdLoadBalancer | Add-AzLoadBalancerFrontendIpConfig -Name $feConfig.Name -PublicIpAddressId $pip.Id > $null
        }
        catch {
            $message = "[PublicFEMigration] An error occured when adding the public front end '$($feConfig.Name)' to the new Standard LB. To recover address the following error, then follow the steps at https://aka.ms/basiclbupgradefailure to retry the migration.`nError message: $_"
            log 'Error' $message -terminateOnError
        }
    }
    log -Message "[PublicFEMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"

    try {
        $ErrorActionPreference = 'Stop'
        Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer > $null
    }
    catch {
        $message = "[PublicFEMigration] An error occured when moving Public IPs to the new Standard Load Balancer. To recover address the following error, then follow the steps at https://aka.ms/basiclbupgradefailure to retry the migration. `nError message: $_"
        log 'Error' $message -terminateOnError
    }

    log -Message "[PublicFEMigration] Public Frontend Migration Completed"
}

Export-ModuleMember -Function PublicFEMigration,PublicIPToStatic
