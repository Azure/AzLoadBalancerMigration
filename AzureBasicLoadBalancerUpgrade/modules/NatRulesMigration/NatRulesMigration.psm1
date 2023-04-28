# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")
function NatRulesMigration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[NatRulesMigration] Initiating Nat Rules Migration"
    $inboundNatRules = $BasicLoadBalancer.InboundNatRules
    $inboundNatPools = $BasicLoadBalancer.InboundNatPools
    foreach ($inboundNatRule in $inboundNatRules) {
        log -Message "[NatRulesMigration] Evaluating adding NAT Rule '$($inboundNatRule.Name)' to Standard Load Balancer"

        try {
            $ErrorActionPreference = "Stop"

            # inbound nat pools will create dynamic inbound nat rules for each VMSS instance where assigned
            # the nat rule name will either be natpoolname.0 or natpoolname.0.nicname.ipconfigname (for more than one ipconfig/natpool combo)
            $inboundNatPoolNamePattern = $inboundNatRule.Name -replace '\.\d{1,3}(\..+?)?$', ''
            log -Message "[NatRulesMigration] Checking if the NAT rule has a name that '$($inboundNatRule.Name)' matches an Inbound NAT Pool name with pattern '$inboundNatPoolNamePattern'"
            If ($matchedNatPool = $inboundNatPools | Where-Object { $_.Name -ieq $inboundNatPoolNamePattern } ) {
                If ($inboundNatRule.FrontendPort -ge $matchedNatPool[0].FrontendPortRangeStart -and 
                    $inboundNatRule.FrontendPort -le $matchedNatPool[0].FrontendPortRangeEnd -and 
                    $inboundNatRule.FrontendIPConfigurationText -eq $matchedNatPool[0].FrontendIPConfigurationText) {
                    
                    log -Severity 'Warning' -Message "[NatRulesMigration] NAT Rule '$($inboundNatRule.Name)' appears to have been dynamically created for Inbound NAT Pool '$($matchedNatPool.Name)'. This rule will not be migrated!"
                    
                    continue
                }
            }
        }
        catch {
            $message = @"
            [NatRulesMigration] Failed to check if inbound nat rule config '$($inboundNatRule.Name)' was created for an Inbound NAT Pool. Migration will continue, FAILED RULE WILL 
            NEED TO BE MANUALLY ADDED to the load balancer. Error: $_
"@
            log "Error" $message
        }

        try {
            $ErrorActionPreference = 'Stop'
            if ([string]::IsNullOrEmpty($inboundNatRule.BackendAddressPool.Id)) {
                $bkeaddpool = $inboundNatRule.BackendAddressPool.Id
            }
            else {
                $bkeaddpool = (Get-AzLoadBalancerBackendAddressPool -LoadBalancer $StdLoadBalancer -Name ($inboundNatRule.BackendAddressPool.Id).split('/')[-1])
            }

            log -Message "[NatRulesMigration] Adding NAT Rule $($inboundNatRule.Name) to Standard Load Balancer"
            $inboundNatRuleConfig = @{
                Name                    = $inboundNatRule.Name
                Protocol                = $inboundNatRule.Protocol
                FrontendPort            = $inboundNatRule.FrontendPort
                BackendPort             = $inboundNatRule.BackendPort
                IdleTimeoutInMinutes    = $inboundNatRule.IdleTimeoutInMinutes
                EnableFloatingIP        = $inboundNatRule.EnableFloatingIP
                EnableTcpReset          = $inboundNatRule.EnableTcpReset
                FrontendIpConfiguration = (Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $StdLoadBalancer -Name ($inboundNatRule.FrontendIpConfiguration.Id).split('/')[-1])
                FrontendPortRangeStart  = $inboundNatRule.FrontendPortRangeStart
                FrontendPortRangeEnd    = $inboundNatRule.FrontendPortRangeEnd
                BackendAddressPool      = $bkeaddpool
            }
            $StdLoadBalancer | Add-AzLoadBalancerInboundNatRuleConfig @inboundNatRuleConfig > $null
        }
        catch {
            $message = @"
            [NatRulesMigration] Failed to add inbound nat rule config '$($inboundNatRule.Name)' to new standard load balancer '$($stdLoadBalancer.Name)' in resource
            group '$($StdLoadBalancer.ResourceGroupName)'. Migration will continue, FAILED RULE WILL NEED TO BE MANUALLY ADDED to the load balancer. Error: $_
"@
            log "Error" $message
        }
    }
    log -Message "[NatRulesMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"

    try {
        $ErrorActionPreference = 'Stop'
        Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer > $null
    }
    catch {
        $message = @"
        [NatRulesMigration] Failed to update new standard load balancer '$($stdLoadBalancer.Name)' in resource
        group '$($StdLoadBalancer.ResourceGroupName)' after attempting to add migrated inbound NAT rule
        configurations. Migration will continue, INBOUND NAT RULES WILL NEED TO BE MANUALLY ADDED to the load
        balancer. Error: $_
"@
        log "Error" $message
    }
    log -Message "[NatRulesMigration] Nat Rules Migration Completed"
}

Export-ModuleMember -Function NatRulesMigration
