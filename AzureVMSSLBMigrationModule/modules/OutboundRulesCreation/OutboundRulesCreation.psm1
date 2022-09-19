# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")
function OutboundRulesCreation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[OutboundRulesCreation] Initiating Outbound Rules Creation"
    $backendAddressPools = $StdLoadBalancer.BackendAddressPools
    foreach ($backendAddressPool in $backendAddressPools) {
        log -Message "[OutboundRulesCreation] Adding Outbound Rule $($backendAddressPool.Name) to Standard Load Balancer"
        try {
            $ErrorActionPreference = 'Stop'
            $outboundRuleConfig = @{
                Name                    = $backendAddressPool.Name
                AllocatedOutboundPort   = 0
                Protocol                = "All"
                EnableTcpReset          = $True
                IdleTimeoutInMinutes    = 4
                FrontendIpConfiguration = (Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $StdLoadBalancer)[0]
                BackendAddressPool      = (Get-AzLoadBalancerBackendAddressPool -LoadBalancer $StdLoadBalancer -Name $backendAddressPool.Name)
            }
            $StdLoadBalancer | Add-AzLoadBalancerOutboundRuleConfig @outboundRuleConfig > $null
        }
        catch {
            $message = @"
                [OutboundRulesCreation] An error occured when adding Outbound Rule '$($backendAddressPool.Name)' to new Standard load
                balancer '$($StdLoadBalancer.Name)'. To recover address the following error, and try again specifying the
                -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup State file located either in this directory or
                the directory specified with -RecoveryBackupPath. `nError message: $_
"@
            log "Error" $message
            Exit
        }

    }
    log -Message "[OutboundRulesCreation] Saving Standard Load Balancer $($StdLoadBalancer.Name)"
    Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer > $null
    log -Message "[OutboundRulesCreation] Outbound Rules Creation Completed"
}

Export-ModuleMember -Function OutboundRulesCreation