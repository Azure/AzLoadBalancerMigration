# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")

function _NatRuleNicMembershipMigration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[NatRuleNicMembershipMigration] Initiating NAT rule VM membership migration"

    log -Message "[NatRuleNicMembershipMigration] Adding original VMs to the new Standard Load Balancer NAT rules"

    # build table of NICs and their ipconfigs and associate them to backend pools
    # this is used to associate the ipconfigs to the backend pools on the NICs in a single operation per NIC
    $natRuleNicTable = @{}
    ForEach ($InboundNATRule in $BasicLoadBalancer.InboundNATRules) {

        # create a subresource to represent the nat rule
        $subResource = New-Object Microsoft.Azure.Commands.Network.Models.PSInboundNatRule
        $subResource.Id = ($StdLoadBalancer.InboundNatRules | Where-Object { $_.Name -eq $InboundNATRule.Name }).Id

        If ($InboundNATRule.BackendIpConfiguration.id) {
            $NatRuleIpConfiguration = $InboundNATRule.BackendIpConfiguration

            $lbNatRuleNicId = ($NatRuleIpConfiguration.Id -split '/ipConfigurations/')[0]
            $ipConfigName = ($NatRuleIpConfiguration.Id -split '/ipConfigurations/')[1]

            # create empty list of ip configs for this NIC if it doesn't exist
            If (!$natRuleNicTable[$lbNatRuleNicId]) {
                $natRuleNicTable[$lbNatRuleNicId] = @(@{ipConfigs = @{} })
            }
            # add ip config with associated nat rule to list
            # create new nat rule list for this ipconfig if one doesn't exist
            If (!$natRuleNicTable[$lbNatRuleNicId].ipConfigs[$ipConfigName]) {

                $natRulesList = New-Object 'System.Collections.Generic.List[Microsoft.Azure.Commands.Network.Models.PSInboundNatRule]'
                $natRulesList.Add($subResource)

                $natRuleNicTable[$lbNatRuleNicId].ipConfigs[$ipConfigName] = @{natRulesList = $natRulesList}
            }
            # add nat rule to existing nat rule list for this ipconfig if the list already exists
            Else {
                $natRuleNicTable[$lbNatRuleNicId].ipConfigs[$ipConfigName].natRulesList.add($subResource)
            }
        }
        Else {
            log -Message "[NatRuleNicMembershipMigration] NAT rule '$($InboundNATRule.Name)' does not have a backend ip configuration, skipping NIC association"
        }
    }

    # loop though nics and associate ipconfigs to backend pools
    $jobs = @()
    ForEach ($nicRecord in $natRuleNicTable.GetEnumerator()) {

        log -Message "[NatRuleNicMembershipMigration] Adding ipconfigs on NIC $($nicRecord.Name.split('/')[-1]) to NAT rules"

        try {
            $nic = Get-AzNetworkInterface -ResourceId $nicRecord.Name
        }
        catch {
            $message = "[NatRuleNicMembershipMigration] An error occured getting the Network Interface '$($nicRecord.Name)'. Check that the NIC exists. To recover, address the cause of the following error, then follow the steps at https://aka.ms/basiclbupgradefailure to retry the migration. Error: $_"
            log 'Error' $message -terminateOnError
        }

        ForEach ($nicIPConfig in $nic.IpConfigurations) {
            $nicIPConfig.loadBalancerInboundNatRules = $natRuleNicTable[$nicRecord.Name].ipConfigs[$nicIPConfig.Name].natRulesList
        }

        $jobs += Set-AzNetworkInterface -NetworkInterface $nic -AsJob
    }

    log -Message "[NatRuleNicMembershipMigration] Waiting for all '$($jobs.count)' NIC NAT Rule association jobs to complete"
    $jobs | Wait-Job -Timeout $defaultJobWaitTimeout | Foreach-Object {
        $job = $_
        If ($job.Error -or $job.State -eq 'Failed') {
            log -Severity Error -Message "Associating NIC with LB NAT Rule failed with the following errors: $($job.error; $job | Receive-Job). Migration will continue--to recover, manually associate NICs with the backend pool after the script completes. See association table: `n $($backendPoolNicTable | ConvertTo-Json -depth 10)"
        }
    }

    log -Message "[NatRuleNicMembershipMigration] NAT Rule Migration Completed"
}
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
            $inboundNatPoolNamePattern = $inboundNatRule.Name -replace '\.\d{1,4}(\..+?)?$', ''
            log -Message "[NatRulesMigration] Checking if the NAT rule has a name that '$($inboundNatRule.Name)' matches an Inbound NAT Pool name with pattern '$inboundNatPoolNamePattern'"
            If ($matchedNatPool = $inboundNatPools | Where-Object { $_.Name -ieq $inboundNatPoolNamePattern } ) {
                If ($inboundNatRule.FrontendPort -ge $matchedNatPool[0].FrontendPortRangeStart -and 
                    $inboundNatRule.FrontendPort -le $matchedNatPool[0].FrontendPortRangeEnd -and 
                    $inboundNatRule.FrontendIPConfigurationText -eq $matchedNatPool[0].FrontendIPConfigurationText) {
                    
                    log -Message "[NatRulesMigration] NAT Rule '$($inboundNatRule.Name)' appears to have been dynamically created for Inbound NAT Pool '$($matchedNatPool.Name)'. This rule will not be migrated and is normal for LBs with NAT Pools."
                    
                    continue
                }
            }
        }
        catch {
            $message = "[NatRulesMigration] Failed to check if inbound nat rule config '$($inboundNatRule.Name)' was created for an Inbound NAT Pool. Migration will continue, FAILED RULE WILL NEED TO BE MANUALLY ADDED to the load balancer. Error: $_"
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
            $message = "[NatRulesMigration] Failed to add inbound nat rule config '$($inboundNatRule.Name)' to new standard load balancer '$($stdLoadBalancer.Name)' in resource group '$($StdLoadBalancer.ResourceGroupName)'. Migration will continue, FAILED RULE WILL NEED TO BE MANUALLY ADDED to the load balancer. Error: $_"
            log "Error" $message
        }
    }
    log -Message "[NatRulesMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"

    if ($StdLoadBalancer.InboundNatRules.Count -eq 0) {
        log -Message "[NatRulesMigration] No NAT Rules to migrate. Skipping save."
        return
    }
    else {
        try {
            $ErrorActionPreference = 'Stop'

            $UpdateLBNATRulesJob = Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer -AsJob

            While ($UpdateLBNATRulesJob.State -eq 'Running') {
                Start-Sleep -Seconds 15
                log -Message "[NatRulesMigration] Waiting for saving standard load balancer $($StdLoadBalancer.Name) job to complete..."
            }

            If ($UpdateLBNATRulesJob.Error -or $UpdateLBNATRulesJob.State -eq 'Failed') {
                Write-Error $UpdateLBNATRulesJob.Error 
            }
        }
        catch {
            $message = "[NatRulesMigration] Failed to update new standard load balancer '$($stdLoadBalancer.Name)' in resource group '$($StdLoadBalancer.ResourceGroupName)' after attempting to add migrated inbound NAT rule configurations. Migration will continue, INBOUND NAT RULES WILL NEED TO BE MANUALLY ADDED to the load balancer. Error: $_"
            log "Error" $message
        }
    }
    log -Message "[NatRulesMigration] Nat Rules Migration Completed"

    _NatRuleNicMembershipMigration -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancer $StdLoadBalancer
}

Export-ModuleMember -Function NatRulesMigration
