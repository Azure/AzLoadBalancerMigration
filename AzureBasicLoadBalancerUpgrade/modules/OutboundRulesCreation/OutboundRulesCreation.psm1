# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")

function OutboundRulesCreation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer,
        [Parameter(Mandatory = $false)][psobject] $scenario
    )
    log -Message "[OutboundRulesCreation] Initiating Outbound Rules Creation"

    If ($scenario.VMsHavePublicIPs -or $scenario.VMSSInstancesHavePublicIPs) {
        #InvalidOperation: OutboundRules for VMs with public IpConfigurations (instance level publicIPs) /subscriptions/.../ipConfigurations/ipconfig1 are not supported
        log -Severity Warning -Message "[OutboundRulesCreation] Skipping OutboundRuleCreation because backend VMs or VMSS Instances have instance-level Public IPs associated, which is not supported in combination with Outbound Rules. Outbound traffic will use the ILIP."
    }
    ElseIf ($scenario.SkipOutboundRuleCreationMultiBE) {
        log -Severity Warning -Message "[OutboundRulesCreation] Skipping OutboundRuleCreation because the Load Balancer has multiple backend pools and an Outbound rule can only have one associated backend pool. MANUALLY CREATE OUTBOUND RULES AFTER MIGRATION."
    }
    Else {
        $backendAddressPools = $StdLoadBalancer.BackendAddressPools
        foreach ($backendAddressPool in $backendAddressPools) {
            log -Message "[OutboundRulesCreation] Adding Outbound Rule $($backendAddressPool.Name) to Standard Load Balancer"
            try {
                $ErrorActionPreference = 'Stop'
                $outboundRuleConfig = @{
                    Name                    = $backendAddressPool.Name
                    AllocatedOutboundPort   = 0
                    Protocol                = "All"
                    EnableTcpReset          = $True
                    IdleTimeoutInMinutes    = 4
                    FrontendIpConfiguration = (Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $StdLoadBalancer)[0]
                    BackendAddressPool      = (Get-AzLoadBalancerBackendAddressPool -LoadBalancer $StdLoadBalancer -Name $backendAddressPool.Name)
                }
                $StdLoadBalancer | Add-AzLoadBalancerOutboundRuleConfig @outboundRuleConfig > $null
            }
            catch {
                $message = @"
                [OutboundRulesCreation] An error occured when adding Outbound Rule '$($backendAddressPool.Name)' to new Standard load
                balancer '$($StdLoadBalancer.Name)'. To recover address the following error, and try again specifying the
                -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup State file located either in this directory or
                the directory specified with -RecoveryBackupPath. `nError message: $_
"@
                log "Error" $message -terminateOnError
            }

        }

        log -Message "[OutboundRulesCreation] Saving Standard Load Balancer $($StdLoadBalancer.Name)"
        Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer > $null

    }
    log -Message "[OutboundRulesCreation] Outbound Rules Creation Completed"
}

Export-ModuleMember -Function OutboundRulesCreation
