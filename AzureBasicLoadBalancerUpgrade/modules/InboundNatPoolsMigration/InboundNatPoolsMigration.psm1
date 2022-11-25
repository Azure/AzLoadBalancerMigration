# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")
function InboundNatPoolsMigration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[InboundNatPoolsMigration] Initiating Inbound NAT Pools Migration"

    $inboundNatPools = $BasicLoadBalancer.InboundNatPools
    foreach ($pool in $inboundNatPools) {
        log -Message "[InboundNatPoolsMigration] Adding Inbound NAT Pool $($pool.Name) to Standard Load Balancer"
        $frontEndIPConfig = Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $StdLoadBalancer -Name ($pool.FrontEndIPConfiguration.Id.split('/')[-1])
        $inboundNatPoolConfig = @{
            Name                    = $pool.Name
            BackendPort             = $pool.backendPort
            Protocol                = $pool.Protocol
            EnableFloatingIP        = $pool.EnableFloatingIP
            EnableTcpReset          = $pool.EnableTcpReset
            FrontendIPConfiguration = $frontEndIPConfig
            FrontendPortRangeStart  = $pool.FrontendPortRangeStart
            FrontendPortRangeEnd    = $pool.FrontendPortRangeEnd
            IdleTimeoutInMinutes    = $pool.IdleTimeoutInMinutes
        }

        try {
            $ErrorActionPreference = 'Stop'
            $StdLoadBalancer | Add-AzLoadBalancerInboundNatPoolConfig @inboundNatPoolConfig > $null 
        }
        catch {
            $message = "[InboundNatPoolsMigration] An error occured when adding Inbound NAT Pool config '$($pool.name)' to the new Standard 
                Load Balancer. The script will continue. MANUALLY CREATE THE FOLLOWING INBOUND NAT POOL CONFIG ONCE THE SCRIPT COMPLETES. 
                `n$($inboundNatPoolConfig | ConvertTo-Json -Depth 5)$_$_"
            log 'Warning' $message
        }

    }
    log -Message "[InboundNatPoolsMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"

    try {
        $ErrorActionPreference = 'Stop'
        Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer > $null
    }
    catch {
        $message = @"
            [InboundNatPoolsMigration] An error occured when adding Inbound NAT Pool config '$($pool.name)' to the new Standard Load Balancer. The script 
            will continue. MANUALLY CREATE THE FOLLOWING INBOUND NAT POOL CONFIG ONCE THE SCRIPT COMPLETES. 
            `n$($StdLoadBalancer | Get-AzLoadBalancerInboundNatPoolConfig | ConvertTo-Json -Depth 5)$_
"@
        log 'Warning' $message
    }

    log -Message "[InboundNatPoolsMigration] Inbound NAT Pools Migration Completed"
}
Export-ModuleMember -Function InboundNatPoolsMigration