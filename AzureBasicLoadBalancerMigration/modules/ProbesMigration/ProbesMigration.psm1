# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")
function ProbesMigration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[ProbesMigration] Initiating Probes Migration"

    $probes = $BasicLoadBalancer.Probes
    foreach ($probe in $probes) {
        log -Message "[ProbesMigration] Adding Probe $($probe.Name) to Standard Load Balancer"
        $probeConfig = @{
            Name              = $probe.Name
            Port              = $probe.Port
            Protocol          = $probe.Protocol
            RequestPath       = $probe.RequestPath
            IntervalInSeconds = $probe.IntervalInSeconds
            ProbeCount        = $probe.NumberOfProbes
        }

        try {
            $ErrorActionPreference = 'Stop'
            $StdLoadBalancer | Add-AzLoadBalancerProbeConfig @probeConfig > $null
        }
        catch {
            $message = @"
            [ProbesMigration] Failed to add health probe config '$($probe.Name)' to new standard load balancer '$($stdLoadBalancer.Name)' in resource 
            group '$($StdLoadBalancer.ResourceGroupName)'. To recover address the following error, and try again specifying the 
            -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup State file located either in this directory or 
            the directory specified with -RecoveryBackupPath. `nError message: $_ 
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
        group '$($StdLoadBalancer.ResourceGroupName)'. To recover address the following error, and try again specifying the 
        -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup State file located either in this directory or 
        the directory specified with -RecoveryBackupPath. `nError message: $_ 
"@
        log "Error" $message
        Exit
    }

    log -Message "[ProbesMigration] Probes Migration Completed"
}
Export-ModuleMember -Function ProbesMigration