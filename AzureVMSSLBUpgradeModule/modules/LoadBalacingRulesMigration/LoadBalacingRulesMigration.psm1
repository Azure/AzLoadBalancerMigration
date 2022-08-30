# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
function LoadBalacingRulesMigration {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[LoadBalacingRulesMigration] Initiating LoadBalacing Rules Migration"
    $loadBalancingRules = $BasicLoadBalancer.LoadBalancingRules
    foreach ($loadBalancingRule in $loadBalancingRules) {
        log -Message "[LoadBalacingRulesMigration] Adding LoadBalacing Rule $($loadBalancingRule.Name) to Standard Load Balancer"
        $loadBalancingRuleConfig = @{
            Name = $loadBalancingRule.Name
            Protocol = $loadBalancingRule.Protocol
            FrontendPort = $loadBalancingRule.FrontendPort
            BackendPort = $loadBalancingRule.BackendPort
            IdleTimeoutInMinutes = $loadBalancingRule.IdleTimeoutInMinutes
            EnableFloatingIP = $loadBalancingRule.EnableFloatingIP
            LoadDistribution = $loadBalancingRule.LoadDistribution
            DisableOutboundSnat = $loadBalancingRule.DisableOutboundSnat
            EnableTcpReset = $loadBalancingRule.EnableTcpReset
            FrontendIPConfiguration = (Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $StdLoadBalancer -Name ($loadBalancingRule.FrontendIpConfiguration.Id).split('/')[-1])
            BackendAddressPool = (Get-AzLoadBalancerBackendAddressPool -LoadBalancer $StdLoadBalancer -Name ($loadBalancingRule.BackendAddressPool.Id).split('/')[-1])
            Probe = (Get-AzLoadBalancerProbeConfig -LoadBalancer $StdLoadBalancer -Name ($loadBalancingRule.Probe.Id).split('/')[-1])
        }
        $StdLoadBalancer | Add-AzLoadBalancerRuleConfig @loadBalancingRuleConfig > $null
    }
    log -Message "[LoadBalacingRulesMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"
    Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer  > $null
    log -Message "[LoadBalacingRulesMigration] LoadBalacing Rules Migration Completed"
}

Export-ModuleMember -Function LoadBalacingRulesMigration