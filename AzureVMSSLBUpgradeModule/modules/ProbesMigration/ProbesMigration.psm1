# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")
function ProbesMigration {
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[ProbesMigration] Initiating Probes Migration"

    $probes = $BasicLoadBalancer.Probes
    foreach ($probe in $probes) {
        log -Message "[ProbesMigration] Adding Probe $($probe.Name) to Standard Load Balancer"
        $probeConfig = @{
            Name = $probe.Name
            Port = $probe.Port
            Protocol = $probe.Protocol
            RequestPath = $probe.RequestPath
            IntervalInSeconds = $probe.IntervalInSeconds
            ProbeCount = $probe.NumberOfProbes
        }
        $StdLoadBalancer | Add-AzLoadBalancerProbeConfig @probeConfig
    }
    log -Message "[ProbesMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"
    Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer
    log -Message "[ProbesMigration] Probes Migration Completed"
}
Export-ModuleMember -Function ProbesMigration