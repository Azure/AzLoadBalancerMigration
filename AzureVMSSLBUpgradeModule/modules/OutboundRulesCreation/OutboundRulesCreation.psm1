# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
function OutboundRulesCreation {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[OutboundRulesCreation] Initiating Outbound Rules Creation"
    $backendAddressPools = $StdLoadBalancer.BackendAddressPools
    foreach ($backendAddressPool in $backendAddressPools) {
        log -Message "[OutboundRulesCreation] Adding Outbound Rule $($backendAddressPool.Name) to Standard Load Balancer"
        $outboundRuleConfig = @{
            Name = $backendAddressPool.Name
            AllocatedOutboundPort = 0
            Protocol = "All"
            EnableTcpReset = $True
            IdleTimeoutInMinutes = 4
            FrontendIpConfiguration = (Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $StdLoadBalancer)[0]
            BackendAddressPool = (Get-AzLoadBalancerBackendAddressPool -LoadBalancer $StdLoadBalancer -Name $backendAddressPool.Name)
        }
        try {
            $ErrorActionPreference = 'Stop'
            $StdLoadBalancer | Add-AzLoadBalancerOutboundRuleConfig @outboundRuleConfig > $null
        }
        catch {
            $message = @"
                [OutboundRulesCreation] An error occured when adding Outbound Rule '$($backendAddressPool.Name)' to new Standard load
                balancer '$($StdLoadBalancer.Name)'. To recover, address the following error, delete the standard LB, redeploy the Basic
                load balancer from the backup' file, add backend pool membership back state file for original pool membership), and retry the migration.  Error: $_
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