# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")
function LoadBalancingRulesMigration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[LoadBalancingRulesMigration] Initiating LoadBalancing Rules Migration"
    $loadBalancingRules = $BasicLoadBalancer.LoadBalancingRules
    foreach ($loadBalancingRule in $loadBalancingRules) {
        log -Message "[LoadBalancingRulesMigration] Adding LoadBalancing Rule $($loadBalancingRule.Name) to Standard Load Balancer"

        # set $probe if LBR has probe
        if ($loadBalancingRule.Probe -ne $null) {
            $probeName = ($loadBalancingRule.Probe.Id).split('/')[-1]
            $probe = Get-AzLoadBalancerProbeConfig -LoadBalancer $StdLoadBalancer -Name $probeName
        }
        else {
            $probe = $null
        }

        try {
            $ErrorActionPreference = 'Stop'
            $loadBalancingRuleConfig = @{
                Name                    = $loadBalancingRule.Name
                Protocol                = $loadBalancingRule.Protocol
                FrontendPort            = $loadBalancingRule.FrontendPort
                BackendPort             = $loadBalancingRule.BackendPort
                IdleTimeoutInMinutes    = $loadBalancingRule.IdleTimeoutInMinutes
                EnableFloatingIP        = $loadBalancingRule.EnableFloatingIP
                LoadDistribution        = $loadBalancingRule.LoadDistribution
                DisableOutboundSnat     = $loadBalancingRule.DisableOutboundSnat
                EnableTcpReset          = $loadBalancingRule.EnableTcpReset
                FrontendIPConfiguration = (Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $StdLoadBalancer -Name ($loadBalancingRule.FrontendIpConfiguration.Id).split('/')[-1])
                BackendAddressPool      = (Get-AzLoadBalancerBackendAddressPool -LoadBalancer $StdLoadBalancer -Name ($loadBalancingRule.BackendAddressPool.Id).split('/')[-1])
                Probe                   = $probe
            }
            $StdLoadBalancer | Add-AzLoadBalancerRuleConfig @loadBalancingRuleConfig > $null
        }
        catch {
            $message = "[LoadBalancingRulesMigration] An error occurred when adding Load Balancing Rule '$($loadBalancingRule.Name)' to new Standard load balancer '$($StdLoadBalancer.Name)'. To recover, address the following error, delete the standard LB, and follow the process at https://aka.ms/basiclbupgradefailure to retry migration. Error: $_"
            log "Error" $message -terminateOnError
        }
    }
    log -Message "[LoadBalancingRulesMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"

    try {
        $ErrorActionPreference = 'Stop'
        Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer > $null
    }
    catch {
        $message = "[LoadBalancingRulesMigration] An error occurred when adding Load Balancing Rules configuration to new Standard load balancer '$($StdLoadBalancer.Name)'. To recover address the following error, https://aka.ms/basiclbupgradefailure. `nError message: $_"
        log "Error" $message -terminateOnError
    }
    log -Message "[LoadBalancingRulesMigration] LoadBalancing Rules Migration Completed"
}

Export-ModuleMember -Function LoadBalancingRulesMigration
