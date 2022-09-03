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

        try {
            $ErrorActionPreference = 'Stop'
            $StdLoadBalancer | Add-AzLoadBalancerProbeConfig @probeConfig > $null
        }
        catch {
            $message = @"
            [ProbesMigration] Failed to add health probe config '$($probe.Name)' to new standard load balancer '$($stdLoadBalancer.Name)' in resource 
            group '$($StdLoadBalancer.ResourceGroupName)'. To recover, address the following error, delete the standard LB ,redeploy the Basic 
            load balancer from the backup 'ARMTemplate-$($BasicLoadBalancer.Name)-$($BasicLoadBalancer.ResourceGroupName)...' file, add backend 
            pool membership back (see the backup '$('State-' + $BasicLoadBalancerName + '-' + $BasicLoadBalancer.ResourceGroupName + '...')' state 
            file for original pool membership), and retry the migration.  `nError: $_ 
"@
            log "Error" $message
            Exit
        }
    }
    log -Message "[ProbesMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"
    try {
        $ErrorActionPreference = 'Stop'
        Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer > $null
    }
    catch {
        $message = @"
        [ProbesMigration] Failed to add health probe config '$($probe.Name)' to new standard load balancer '$($stdLoadBalancer.Name)' in resource 
        group '$($StdLoadBalancer.ResourceGroupName)'. To recover, address the following error, delete the standard LB ,redeploy the Basic 
        load balancer from the backup 'ARMTemplate-$($BasicLoadBalancer.Name)-$($BasicLoadBalancer.ResourceGroupName)...' file, add backend 
        pool membership back (see the backup '$('State-' + $BasicLoadBalancerName + '-' + $BasicLoadBalancer.ResourceGroupName + '...')' state 
        file for original pool membership), and retry the migration.  Error: $_ 
"@
        log "Error" $message
        Exit
    }

    log -Message "[ProbesMigration] Probes Migration Completed"
}
Export-ModuleMember -Function ProbesMigration