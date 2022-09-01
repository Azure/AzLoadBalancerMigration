# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
function PrivateFEMigration {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[PrivateFEMigration] Initiating Private Frontend Migration"
    $basicLoadBalancerFeConfig = $BasicLoadBalancer.FrontendIpConfigurations

    # Change allocation method to staic and SKU to Standard
    foreach ($feConfig in $basicLoadBalancerFeConfig) {
        $privateIP = $feConfig.PrivateIpAddress
        $vnetRG = $feConfig.Subnet.Id.split('/')[4]
        $vnetName = $feConfig.Subnet.Id.split('/')[7]

        $ipAvailability = Test-AzPrivateIPAddressAvailability -ResourceGroupName $vnetRG -VirtualNetworkName $vnetName
        If (!$ipAvailability.Available) {
            log 'Error' "[PrivateFEMigration] The private IP address '$privateIP' in VNET '$vnetName', resource group '$vnetRG' is not available for allocation; another new device may have claimed it."
            Exit
        }

        $StdLoadBalancer | Add-AzLoadBalancerFrontendIpConfig -Name $feConfig.Name -PrivateIPAddress $privateIP > $null
    }
    log -Message "[PrivateFEMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"

    try {
        $ErrorActionPreference = 'Stop'
        Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer > $null
    }
    catch {
        $message = "[PrivateFEMigration] An error occured when moving private IPs to the new Standard Load Balancer. $_"
        log 'Error' $message
        Exit
    }

    log -Message "[PrivateFEMigration] Private Frontend Migration Completed"
}

Export-ModuleMember -Function PrivateFEMigration