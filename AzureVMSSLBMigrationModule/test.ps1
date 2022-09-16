function OutboundRulesCreation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    #log -Message "[OutboundRulesCreation] Initiating Outbound Rules Creation"
    $backendAddressPools = $StdLoadBalancer.BackendAddressPools
    foreach ($backendAddressPool in $backendAddressPools) {
        #log -Message "[OutboundRulesCreation] Adding Outbound Rule $($backendAddressPool.Name) to Standard Load Balancer"
        $outboundRuleConfig = @{
            Name                    = $($backendAddressPool.Name + "2")
            AllocatedOutboundPort   = 0
            Protocol                = "All"
            EnableTcpReset          = $True
            IdleTimeoutInMinutes    = 4
            FrontendIpConfiguration = (Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $StdLoadBalancer)
            BackendAddressPool      = (Get-AzLoadBalancerBackendAddressPool -LoadBalancer $StdLoadBalancer -Name $backendAddressPool.Name)
        }
        try {
            $StdLoadBalancer | Add-AzLoadBalancerOutboundRuleConfig @outboundRuleConfig -ErrorAction Stop > $null
        }
        catch {
            Write-Output "WARNING: Message is --> " $_
        }

    }
    #log -Message "[OutboundRulesCreation] Saving Standard Load Balancer $($StdLoadBalancer.Name)"
    try {
        Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer -ErrorAction Stop > $null
    }
    catch {
        Write-Output "WARNING: Message is --> " $_
    }

    #log -Message "[OutboundRulesCreation] Outbound Rules Creation Completed"
}

