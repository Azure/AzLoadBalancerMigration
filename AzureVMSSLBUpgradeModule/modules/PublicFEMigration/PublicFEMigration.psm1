# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
function PublicFEMigration {
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
            log -Message "[PublicFEMigration] $($pip.Name) was using Dynamic IP or Basic SKU, changing to Static IP allocation method and Standard SKU." -Severity "Warning"
            $pip.PublicIpAllocationMethod = "Static"
            $pip.Sku.Name = "Standard"

            try {
                $ErrorActionPreference = 'Stop'
                Set-AzPublicIpAddress -PublicIpAddress $pip > $null
            }
            catch {
                $message = "[PublicFEMigration] An error occured when upgrading public IP '$($pip.Name)' from Basic to Standard SKU. $_"
                log 'Error' $message
                Exit
            }
        }
        #$StdLoadBalancer | Add-AzLoadBalancerFrontendIpConfig -Name $feConfig.Name -PublicIpAddressId $pip.Id | Set-AzLoadBalancer
        $StdLoadBalancer | Add-AzLoadBalancerFrontendIpConfig -Name $feConfig.Name -PublicIpAddressId $pip.Id > $null
    }
    log -Message "[PublicFEMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"

    try {
        $ErrorActionPreference = 'Stop'
        Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer > $null
    }
    catch {
        $message = "[PublicFEMigration] An error occured when moving Public IPs to the new Standard Load Balancer. $_"
        log 'Error' $message
        Exit
    }

    log -Message "[PublicFEMigration] Public Frontend Migration Completed"
}

Export-ModuleMember -Function PublicFEMigration