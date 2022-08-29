# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
function NatRulesMigration {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[NatRulesMigration] Initiating Nat Rules Migration Migration"
    $inboundNatRules = $BasicLoadBalancer.InboundNatRules
    foreach ($inboundNatRule in $inboundNatRules) {
        log -Message "[NatRulesMigration] Adding Nat Rule $($inboundNatRule.Name) to Standard Load Balancer"
        $inboundNatRuleConfig = @{
            Name = $inboundNatRule.Name
            Protocol = $inboundNatRule.Protocol
            FrontendPort = $inboundNatRule.FrontendPort
            BackendPort = $inboundNatRule.BackendPort
            IdleTimeoutInMinutes = $inboundNatRule.IdleTimeoutInMinutes
            EnableFloatingIP = $inboundNatRule.EnableFloatingIP
            EnableTcpReset = $inboundNatRule.EnableTcpReset
            FrontendIpConfiguration = (Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $StdLoadBalancer -Name ($inboundNatRule.FrontendIpConfiguration.Id).split('/')[-1])
            FrontendPortRangeStart = $inboundNatRule.FrontendPortRangeStart
            FrontendPortRangeEnd = $inboundNatRule.FrontendPortRangeEnd
            BackendAddressPool = (Get-AzLoadBalancerBackendAddressPool -LoadBalancer $StdLoadBalancer -Name ($inboundNatRule.BackendAddressPool.Id).split('/')[-1])
        }
        $StdLoadBalancer | Add-AzLoadBalancerInboundNatRuleConfig @inboundNatRuleConfig
    }
    log -Message "[NatRulesMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"
    Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer
    log -Message "[NatRulesMigration] Nat Rules Migration Completed"
}

Export-ModuleMember -Function NatRulesMigration