# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")
function PrivateFEMigration {
    [CmdletBinding()]
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
        $vnetName = $feConfig.Subnet.Id.split('/')[8]

        $ipAvailability = Test-AzPrivateIPAddressAvailability -ResourceGroupName $vnetRG -VirtualNetworkName $vnetName -IPAddress $privateIP
        If (!$ipAvailability.Available) {
            $message = @"
                [PrivateFEMigration] The private IP address '$privateIP' in VNET '$vnetName', resource group '$vnetRG' is not available for 
                allocation; another new device may have claimed it. To recover, remove the device that claimed the IP '$privateIP' from the 
                VNET, then try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup State file located
                either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
            log 'Error' $message -terminateOnError
        }

        try {
            $ErrorActionPreference = 'Stop'
            $StdLoadBalancer | Add-AzLoadBalancerFrontendIpConfig -Name $feConfig.Name -PrivateIPAddress $privateIP -SubnetId $feConfig.Subnet.Id > $null
        }
        catch {
            $message = @"
                [PrivateFEMigration] Failed to add FrontEnd Config '$($feConfig.Name)'. To recover address the following error, and try again specifying the 
                -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup State file located either in this directory or 
                the directory specified with -RecoveryBackupPath. `nError message: $_
"@
            log 'Error' $message -terminateOnError
        }
    }
    log -Message "[PrivateFEMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"

    try {
        $ErrorActionPreference = 'Stop'
        Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer > $null
    }
    catch {
        $message = @"
            [PrivateFEMigration] An error occured when moving private IPs to the new Standard Load Balancer. To recover address the following error, and try again specifying the 
            -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup State file located either in this directory or 
            the directory specified with -RecoveryBackupPath. `nError message: $_
"@
        log 'Error' $message -terminateOnError
    }

    log -Message "[PrivateFEMigration] Private Frontend Migration Completed"
}

Export-ModuleMember -Function PrivateFEMigration