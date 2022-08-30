# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
function InboundNatPoolsMigration {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[InboundNatPoolsMigration] Initiating Inbound NAT Pools Migration"

    $inboundNatPools = $BasicLoadBalancer.InboundNatPools
    foreach ($pool in $inboundNatPools) {
        log -Message "[InboundNatPoolsMigration] Adding Inbound NAT Pool $($pool.Name) to Standard Load Balancer"
        $inboundNatPoolConfig = @{
            Name = $pool.Name
            BackendPort = $pool.backendPort
            Protocol = $pool.Protocol
            EnableFloatingIP = $pool.EnableFloatingIP
            EnableTcpReset = $pool.EnableTcpReset
            FrontendIPConfiguration = $pool.FrontendIPConfiguration
            FrontendPortRangeStart = $pool.FrontendPortRangeStart
            FrontendPortRangeEnd = $pool.FrontendPortRangeEnd
            IdleTimeoutInMinutes = $pool.IdleTimeoutInMinutes
        }
        $StdLoadBalancer | Add-AzLoadBalancerInboundNatPoolConfig @poolConfig > $null
    }
    log -Message "[InboundNatPoolsMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"
    Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer > $null
    log -Message "[InboundNatPoolsMigration] Inbound NAT Pools Migration Completed"
}
Export-ModuleMember -Function InboundNatPoolsMigration