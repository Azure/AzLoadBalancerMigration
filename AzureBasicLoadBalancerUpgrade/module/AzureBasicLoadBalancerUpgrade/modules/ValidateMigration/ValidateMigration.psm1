Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/NsgCreation/NsgCreation.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/ValidateScenario/ValidateScenario.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/GetVmssFromBasicLoadBalancer/GetVmssFromBasicLoadBalancer.psd1")

Function ValidateMigration {
    param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $false)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $false)][switch] $OutputMigrationValiationObj,
        # in the default LB upgrade, NAT pools are migrated. Specify $false for this parameter if you did not migrate NAT Pools to NAT Rules
        [Parameter(Mandatory = $false)][boolean] $natPoolsMigratedToNatRules = $true 
    )

    log -Message "[ValidateMigration] Initiating Validation of Migration for basic LB '$($BasicLoadBalancer.Name)' to standard LB '$($standardLoadBalancerName)')'"

    $validationResult = @{
        "migrationSuccessful" = $false
        "failedValidations"   = @()
        "passedValidations"   = @()
        "warnValidations"     = @()
    }

    $scenario = New-Object -TypeName psobject -Property @{
        'ExternalOrInternal'              = ''
        'BackendType'                     = ''
        'VMsHavePublicIPs'                = $false
        'VMSSInstancesHavePublicIPs'      = $false
        'SkipOutboundRuleCreationMultiBE' = $false
    }

    If ([string]::IsNullOrEmpty($StandardLoadBalancerName)) {
        log -Message "[ValidateMigration] Standard Load Balancer name not specified, assuming reusing Basic Load Balancer name '$($BasicLoadBalancer.Name)'"
        $StandardLoadBalancerName = $BasicLoadBalancer.Name
    }
    
    # detecting if source load balancer is internal or external-facing
    If (![string]::IsNullOrEmpty($BasicLoadBalancer.FrontendIpConfigurations[0].PrivateIpAddress)) {
        $scenario.ExternalOrInternal = 'Internal'
    }
    ElseIf (![string]::IsNullOrEmpty($BasicLoadBalancer.FrontendIpConfigurations[0].PublicIpAddress)) {
        $scenario.ExternalOrInternal = 'External'
    }

    # getting backend type
    $scenario.backendType = _GetScenarioBackendType -BasicLoadBalancer $BasicLoadBalancer -skipLogging
    log -Message "[ValidateMigration] Backend type: $($scenario.backendType)"

    # validate the standard load balancer exists and is standard SKU
    $standardLoadBalancer = Get-AzLoadBalancer -Name $StandardLoadBalancerName -ResourceGroupName $BasicLoadBalancer.ResourceGroupName -ErrorAction SilentlyContinue

    If ($null -eq $standardLoadBalancer) {
        log -Message "[ValidateMigration] Standard Load Balancer does not exist" -Severity Error
        $validationResult.failedValidations += "Standard Load Balancer does not exist"
    }
    Else {
        log -Message "[ValidateMigration] Standard Load Balancer exists" -Severity Information
        $validationResult.passedValidations += "Standard Load Balancer exists"
    }

    If ($standardLoadBalancer.Sku.Name -ne "Standard") {
        log -Message "[ValidateMigration] Standard Load Balancer is not Standard SKU" -Severity Error
        $validationResult.failedValidations += "Standard Load Balancer is not Standard SKU"
    }
    Else {
        log -Message "[ValidateMigration] Standard Load Balancer is Standard SKU" -Severity Information
        $validationResult.passedValidations += "Standard Load Balancer is Standard SKU"
    }

    # validate the standard load balancer has the same number of frontend IPs as the basic load balancer
    If ($standardLoadBalancer.FrontendIPConfigurations.Count -ne $BasicLoadBalancer.FrontendIPConfigurations.Count) {
        log -Message "[ValidateMigration] Standard Load Balancer does not have the same number of frontend IPs ('$($standardLoadBalancer.FrontendIPConfigurations.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.FrontendIPConfigurations.Count)')" -Severity Error
        $validationResult.failedValidations += "Standard Load Balancer does not have the same number of frontend IPs ('$($standardLoadBalancer.FrontendIPConfigurations.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.FrontendIPConfigurations.Count)')"
    }
    Else {
        log -Message "[ValidateMigration] Standard Load Balancer has the same number of frontend IPs ('$($standardLoadBalancer.FrontendIPConfigurations.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.FrontendIPConfigurations.Count)')"
        $validationResult.passedValidations += "Standard Load Balancer has the same number of frontend IPs ('$($standardLoadBalancer.FrontendIPConfigurations.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.FrontendIPConfigurations.Count)')"
    }

    # validate the standard load balancer has the same number of backend pools as the basic load balancer
    ## when nat pools where not migrated to nat rules
    If (!$natPoolsMigratedToNatRules) {
        If ($standardLoadBalancer.BackendAddressPools.Count -ne $BasicLoadBalancer.BackendAddressPools.Count) {
            log -Message "[ValidateMigration] Standard Load Balancer does not have the same number of backend pools ('$($standardLoadBalancer.BackendAddressPools.Count)') as the Basic Load Balancer ('$($BasicLoadBalancer.BackendAddressPools.Count)')" -Severity Error
            $validationResult.failedValidations += "Standard Load Balancer does not have the same number of backend pools ('$($standardLoadBalancer.BackendAddressPools.Count)') as the Basic Load Balancer ('$($BasicLoadBalancer.BackendAddressPools.Count)')"
        }
        Else {
            log -Message "[ValidateMigration] Standard Load Balancer has the same number of backend pools ('$($standardLoadBalancer.BackendAddressPools.Count)') as the Basic Load Balancer ('$($BasicLoadBalancer.BackendAddressPools.Count)')" -Severity Information
            $validationResult.passedValidations += "Standard Load Balancer has the same number of backend pools ('$($standardLoadBalancer.BackendAddressPools.Count)') as the Basic Load Balancer ('$($BasicLoadBalancer.BackendAddressPools.Count)')"
        }
    }
    ## when nat pools were migrated to nat rules
    Else {
        # add the number of backend pools created for NAT Pool migration to NAT rules
        $targetBackendPoolCount = $BasicLoadBalancer.BackendAddressPools.Count + $BasicLoadBalancer.InboundNatPools.Count

        If ($standardLoadBalancer.BackendAddressPools.Count -ne $targetBackendPoolCount) {
            log -Message "[ValidateMigration] Standard Load Balancer does not have the same number of backend pools plus the count added for NAT Pool migration ('$($targetBackendPoolCount)') as the Basic Load Balancer ('$($BasicLoadBalancer.BackendAddressPools.Count)')" -Severity Error
            $validationResult.failedValidations += "Standard Load Balancer does not have the same number of backend pools plus the count added for NAT Pool migration ('$($stbBackendPoolCountMinusNATPools)') as the Basic Load Balancer ('$($BasicLoadBalancer.BackendAddressPools.Count)')"
        }
        Else {
            log -Message "[ValidateMigration] Standard Load Balancer has the same number of backend pools plus the count added for NAT Pool migration ('$($stbBackendPoolCountMinusNATPools)') as the Basic Load Balancer ('$($BasicLoadBalancer.BackendAddressPools.Count)')" -Severity Information
            $validationResult.passedValidations += "Standard Load Balancer has the same number of backend pools plus the count added for NAT Pool migration ('$($stbBackendPoolCountMinusNATPools)') as the Basic Load Balancer ('$($BasicLoadBalancer.BackendAddressPools.Count)')"
        }
    }

    # validate the standard load balancer has the same number of load balancing rules as the basic load balancer
    If ($standardLoadBalancer.LoadBalancingRules.Count -ne $BasicLoadBalancer.LoadBalancingRules.Count) {
        log -Message "[ValidateMigration] Standard Load Balancer does not have the same number of load balancing rules ('$($standardLoadBalancer.LoadBalancingRules.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.LoadBalancingRules.Count)')" -Severity Error
        $validationResult.failedValidations += "Standard Load Balancer does not have the same number of load balancing rules ('$($standardLoadBalancer.LoadBalancingRules.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.LoadBalancingRules.Count)')"
    }
    Else {
        log -Message "[ValidateMigration] Standard Load Balancer has the same number of load balancing rules ('$($standardLoadBalancer.LoadBalancingRules.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.LoadBalancingRules.Count)')" -Severity Information
        $validationResult.passedValidations += "Standard Load Balancer has the same number of load balancing rules ('$($standardLoadBalancer.LoadBalancingRules.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.LoadBalancingRules.Count)')"
    }

    # validate the standard load balancer has the same number of probes as the basic load balancer
    If ($standardLoadBalancer.Probes.Count -ne $BasicLoadBalancer.Probes.Count) {
        log -Message "[ValidateMigration] Standard Load Balancer does not have the same number of health probes ('$($standardLoadBalancer.Probes.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.Probes.Count)')" -Severity Error
        $validationResult.failedValidations += "Standard Load Balancer does not have the same number of health probes ('$($standardLoadBalancer.Probes.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.Probes.Count)')"
    }
    Else {
        log -Message "[ValidateMigration] Standard Load Balancer has the same number of health probes ('$($standardLoadBalancer.Probes.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.Probes.Count)')" -Severity Information
        $validationResult.passedValidations += "Standard Load Balancer has the same number of health probes ('$($standardLoadBalancer.Probes.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.Probes.Count)')"
    }

    # validate the standard load balancer has the same number of inbound NAT rules as the basic load balancer
    If ($natPoolsMigratedToNatRules) {
        # each non nat pool nat rule will be migrated - may be less than the count of nat pools if nat pools are empty
        # each nat pool will create a nat rule
        $nonNATPoolNATRulesCount = $BasicLoadBalancer.InboundNatRules | Where-Object { $_.BackendIPConfiguration -and $_.BackendIPConfiguration.Id -notlike '*Microsoft.Compute/virtualMachineScaleSets*' } | Measure-Object | Select-Object -ExpandProperty Count
        $natPoolCount = $BasicLoadBalancer.InboundNatPools.Count

        $targetNatRuleCount = $nonNATPoolNATRulesCount + $natPoolCount

        If ($standardLoadBalancer.InboundNatRules.Count -ne $targetNatRuleCount) {
            log -Message "[ValidateMigration] Standard Load Balancer does not have the expected number of NAT Rules ('$($targetNatRuleCount)') when NAT Pools are migrated to NAT Rules (one per NAT Pool plus original NAT Rules). Standard load balancer has: '$($standardLoadBalancer.InboundNatRules.Count)'"
            $validationResult.failedValidations += "Standard Load Balancer does not have the expected number of NAT Rules ('$($targetNatRuleCount)') when NAT Pools are migrated to NAT Rules (one per NAT Pool plus original NAT Rules). Standard load balancer has: '$($standardLoadBalancer.InboundNatRules.Count)'"
        }
        Else {
            log -Message "[ValidateMigration] Standard Load Balancer has the expected number of NAT Rules ('$($targetNatRuleCount)') when NAT Pools are migrated to NAT Rules (one per NAT Pool plus original NAT Rules). Standard load balancer has: '$($standardLoadBalancer.InboundNatRules.Count)'"
            $validationResult.passedValidations += "Standard Load Balancer has the expected number of NAT Rules ('$($targetNatRuleCount)') when NAT Pools are migrated to NAT Rules (one per NAT Pool plus original NAT Rules). Standard load balancer has: '$($standardLoadBalancer.InboundNatRules.Count)'"
        }
    }
    Else {
        If ($standardLoadBalancer.InboundNatRules.Count -ne $BasicLoadBalancer.InboundNatRules.Count) {
            log -Message "[ValidateMigration] Standard Load Balancer does not have the same number of inbound NAT rules ('$($standardLoadBalancer.InboundNatRules.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatRules.Count)') " -Severity Error
            $validationResult.failedValidations += "Standard Load Balancer does not have the same number of inbound NAT rules ('$($standardLoadBalancer.InboundNatRules.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatRules.Count)')"
        }
        Else {
            log -Message "[ValidateMigration] Standard Load Balancer has the same number of inbound NAT rules ('$($standardLoadBalancer.InboundNatRules.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatRules.Count)') " -Severity Information
            $validationResult.passedValidations += "Standard Load Balancer has the same number of inbound NAT rules ('$($standardLoadBalancer.InboundNatRules.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatRules.Count)')"
        }
    }

    # validate the standard load balancer inbound nat rules have the same backend ip configurations as the basic load balancer
    $stdLoadBalancerNatRuleBackendIPConfigs = $standardLoadBalancer.InboundNatRules.BackendIpConfiguration.Id
    $basicLoadBalancerNatRuleBackendIPConfigs = $basicLoadBalancer.InboundNatRules.BackendIpConfiguration.Id
    If (!$natPoolsMigratedToNatRules) {
        # check that all basic load balancer nat rule backend ip configs are in the standard load balancer nat rule backend ip configs
        ForEach ($basicLoadBalancerNatRuleBackendIPConfig in $basicLoadBalancerNatRuleBackendIPConfigs) {
            If ($stdLoadBalancerNatRuleBackendIPConfigs -notcontains $basicLoadBalancerNatRuleBackendIPConfig) {
                log -Message "[ValidateMigration] Standard Load Balancer is missing Basic Load Balancer NAT rule backend IP configuration '$basicLoadBalancerNatRuleBackendIPConfig'" -Severity Error
                $validationResult.failedValidations += "Standard Load Balancer is missing Basic Load Balancer NAT rule backend IP configuration '$basicLoadBalancerNatRuleBackendIPConfig'"
            }
            Else {
                log -Message "[ValidateMigration] Standard Load Balancer has Basic Load Balancer NAT rule backend IP configuration '$basicLoadBalancerNatRuleBackendIPConfig'" -Severity Information
                $validationResult.passedValidations += "Standard Load Balancer has Basic Load Balancer NAT rule backend IP configuration '$basicLoadBalancerNatRuleBackendIPConfig'"
            }
        }
        # check that all standard load balancer nat rule backend ip configs are in the basic load balancer nat rule backend ip configs
        ForEach ($stdLoadBalancerNatRuleBackendIPConfig in $stdLoadBalancerNatRuleBackendIPConfigs) {
            If ($basicLoadBalancerNatRuleBackendIPConfigs -notcontains $stdLoadBalancerNatRuleBackendIPConfig) {
                log -Message "[ValidateMigration] Basic Load Balancer is missing Standard Load Balancer NAT rule backend IP configuration '$stdLoadBalancerNatRuleBackendIPConfig'" -Severity Error
                $validationResult.failedValidations += "Basic Load Balancer is missing Standard Load Balancer NAT rule backend IP configuration '$stdLoadBalancerNatRuleBackendIPConfig'"
            }
            Else {
                log -Message "[ValidateMigration] Basic Load Balancer has Standard Load Balancer NAT rule backend IP configuration '$stdLoadBalancerNatRuleBackendIPConfig'" -Severity Information
                $validationResult.passedValidations += "Basic Load Balancer has Standard Load Balancer NAT rule backend IP configuration '$stdLoadBalancerNatRuleBackendIPConfig'"
            }
        }
    }
    Else {
        # compare count of nat rule backend IP configs plus the count of migrated nat pools
        ## nat rule ip configs except for those created by NAT Pool members--which don't exist after NAT Pool to NAT rule migration
        $basicLoadBalancerNatRuleBackendIPConfigsAdj = $basicLoadBalancerNatRuleBackendIPConfigs | Where-Object { $_ -notlike '*Microsoft.Compute/virtualMachineScaleSets*' }
        If ($basicLoadBalancerNatRuleBackendIPConfigsAdj.count -ne $stdLoadBalancerNatRuleBackendIPConfigs.count) {
            log -Message "[ValidateMigration] Standard Load Balancer's count of NAT rule backend IP configurations ('$($stdLoadBalancerNatRuleBackendIPConfigs.count)') does not match the expected count ('$($basicLoadBalancerNatRuleBackendIPConfigsAdj.count)'), adjusted for NAT Pool migrations. Basic LB NAT Rule IP Configs: '$($basicLoadBalancerNatRuleBackendIPConfigsAdj -join ';')' Standard LB NAT Rule IP Configs: '$($stdLoadBalancerNatRuleBackendIPConfigs -join ';')'" -Severity Error
            $validationResult.failedValidations += "Standard Load Balancer's count of NAT rule backend IP configurations ('$($stdLoadBalancerNatRuleBackendIPConfigs.count)') does not match the expected count ('$($basicLoadBalancerNatRuleBackendIPConfigsAdj.count)'), adjusted for NAT Pool migrations. Basic LB NAT Rule IP Configs: '$($basicLoadBalancerNatRuleBackendIPConfigsAdj -join ';')' Standard LB NAT Rule IP Configs: '$($stdLoadBalancerNatRuleBackendIPConfigs -join ';')'"
        }
        Else {
            log -Message "[ValidateMigration] Standard Load Balancer's NAT Rules have the same backend IP configurations count as Basic Load Balancer's NAT rules" -Severity Information
            $validationResult.passedValidations += "Standard Load Balancer's NAT Rules have the same backend IP configurations count as Basic Load Balancer's NAT rules"
        }
    }

    # validate the standard load balancer has the same number of inbound NAT pools as the basic load balancer
    If (!$natPoolsMigratedToNatRules) {
        If ($standardLoadBalancer.InboundNatPools.Count -ne $BasicLoadBalancer.InboundNatPools.Count) {
            log -Message "[ValidateMigration] Standard Load Balancer does not have the same number of inbound NAT pools ('$($standardLoadBalancer.InboundNatPools.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatPools.Count)')." -Severity Error
            $validationResult.failedValidations += "Standard Load Balancer does not have the same number of inbound NAT pools ('$($standardLoadBalancer.InboundNatPools.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatPools.Count)'). If the Basic Load Balancer had NAT Pools with no membership and NAT Pools were migrated to NAT Rules, this could be expected."
        }
        Else {
            log -Message "[ValidateMigration] Standard Load Balancer has the same number of inbound NAT pools ('$($standardLoadBalancer.InboundNatPools.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatPools.Count)')" -Severity Information
            $validationResult.passedValidations += "Standard Load Balancer has the same number of inbound NAT pools ('$($standardLoadBalancer.InboundNatPools.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatPools.Count)')"
        }
    }
    Else {
        If ($standardLoadBalancer.InboundNatPools.Count -ne 0) {
            log -Message "[ValidateMigration] Standard Load Balancer has inbound NAT pools, but migration was configured to upgrade them to NAT Rules" -Severity Error
            $validationResult.failedValidations += "Standard Load Balancer has inbound NAT pools, but migration was configured to upgrade them to NAT Rules"
        }
        Else {
            log -Message "[ValidateMigration] Standard Load Balancer has no inbound NAT pools--migration was configured to upgrade them to NAT Rules" -Severity Information
            $validationResult.passedValidations += "Standard Load Balancer has no inbound NAT pools--migration was configured to upgrade them to NAT Rules"
        }
    }

    # validate the standard load balancer has outbound rules
    If ($standardLoadBalancer.OutboundRules.Count -eq 0 -and $scenario.ExternalOrInternal -eq "External") {
        log -Message "[ValidateMigration] Standard Load Balancer does not have outbound rules" -Severity Warning
        $validationResult.warnValidations += "Standard Load Balancer does not have outbound rules"
    }
    ElseIf ($scenario.ExternalOrInternal -ne "Internal") {
        log -Message "[ValidateMigration] Standard Load Balancer has outbound rules ('$($standardLoadBalancer.OutboundRules.Count)')" -Severity Information
        $validationResult.passedValidations += "Standard Load Balancer has outbound rules ('$($standardLoadBalancer.OutboundRules.Count)')"
    }

    # validate the standard load balancer frontend IP addresses are the same as the basic load balancer frontend IP addresses
    If ($scenario.ExternalOrInternal -eq 'Internal') {
        $basicLoadBalancerFrontendIPs = $BasicLoadBalancer.FrontendIPConfigurations.properties.privateIPAddress
        $standardLoadBalancerFrontendIPs = $standardLoadBalancer.FrontendIPConfigurations.properties.privateIPAddress

        ForEach ($basicLoadBalancerFrontendIP in $basicLoadBalancerFrontendIPs) {
            If ($standardLoadBalancerFrontendIPs -notcontains $basicLoadBalancerFrontendIP) {
                log -Message "[ValidateMigration] Standard Load Balancer is missing Basic Load Balancer private IP address '$basicLoadBalancerFrontendIP'" -Severity Error
                $validationResult.failedValidations += "Standard Load Balancer is missing Basic Load Balancer private IP address '$basicLoadBalancerFrontendIP'"
            }
            Else {
                log -Message "[ValidateMigration] Standard Load Balancer has Basic Load Balancer private IP address '$basicLoadBalancerFrontendIP'" -Severity Information
                $validationResult.passedValidations += "Standard Load Balancer has Basic Load Balancer private IP address '$basicLoadBalancerFrontendIP'"
            }
        }
    }
    ElseIf ($scenario.ExternalOrInternal -eq 'External') {
        $basicLoadBalancerFrontendIPs = $BasicLoadBalancer.FrontendIPConfigurations.publicIPAddress.id
        $standardLoadBalancerFrontendIPs = $standardLoadBalancer.FrontendIPConfigurations.publicIPAddress.id

        ForEach ($basicLoadBalancerFrontendIP in $basicLoadBalancerFrontendIPs) {
            If ($standardLoadBalancerFrontendIPs -notcontains $basicLoadBalancerFrontendIP) {
                log -Message "[ValidateMigration] External Standard Load Balancer is missing Basic Load Balancer public IP address '$basicLoadBalancerFrontendIP'" -Severity Error
                $validationResult.failedValidations += "External Standard Load Balancer is missing Basic Load Balancer public IP address '$basicLoadBalancerFrontendIP'"
            }
            Else {
                log -Message "[ValidateMigration] External Standard Load Balancer has Basic Load Balancer public IP address '$basicLoadBalancerFrontendIP'" -Severity Information
                $validationResult.passedValidations += "External Standard Load Balancer has Basic Load Balancer public IP address '$basicLoadBalancerFrontendIP'"
            }
        }
    }

    # validate that the standard load balancer backend pool membership matches the basic load balancer backend pool membership
    $basicLoadBalancerBackendPools = $BasicLoadBalancer.BackendAddressPools
    $standardLoadBalancerBackendPools = $standardLoadBalancer.BackendAddressPools

    ForEach ($basicBackendAddressPool in $basicLoadBalancerBackendPools) {
        $matchedStdPool = $standardLoadBalancerBackendPools | Where-Object { $_.Name -eq $basicBackendAddressPool.Name }

        $differentMembership = Compare-Object $matchedStdPool.BackendIpConfigurations $basicBackendAddressPool.BackendIpConfigurations -Property Id

        If ($differentMembership) {
            ForEach ($membership in $differentMembership) {
                switch ($membership.sideIndicator) {
                    '<=' {
                        log -Message "[ValidateMigration] Standard Load Balancer pool '$($matchedStdPool.name)' has extra member '$($membership.Id)'" -Severity Error
                        $validationResult.failedValidations += "Standard Load Balancer pool '$($matchedStdPool.name)' is missing Basic Load Balancer backend pool membership '$($membership.Id)'"
                    }
                    '=>' {
                        log -Message "[ValidateMigration] Standard Load Balancer pool '$($matchedStdPool.name)' is missing member '$($membership.Id)'" -Severity Error
                        $validationResult.failedValidations += "Standard Load Balancer pool '$($matchedStdPool.name)' is missing Basic Load Balancer backend pool membership '$($membership.Id)'"
                    }
                }
            }
        }
        Else {
            log -Message "[ValidateMigration] Standard Load Balancer pool '$($matchedStdPool.name)' has the same membership as Basic Load Balancer pool '$($basicBackendAddressPool.name)'" -Severity Information
            $validationResult.passedValidations += "Standard Load Balancer pool '$($matchedStdPool.name)' has the same membership as Basic Load Balancer pool '$($basicBackendAddressPool.name)'"
        }
    }

    If ($validationResult.failedValidations.Count -eq 0) {
        $validationResult.migrationSuccessful = $true
    }
    ElseIf ($validationResult.failedValidations.Count -gt 0) {
        $validationResult.migrationSuccessful = $false
    }

    # validate backend members have NSGs which allow the same ports as the load balancing rules
    If ($scenario.ExternalOrInternal -eq 'External') {
        switch ($scenario.BackendType) {
            'VM' {
                $nicsNeedingNewNSG, $nsgIDsToUpdate = _GetVMNSG -BasicLoadBalancer $BasicLoadBalancer -skipLogging

                If ($nicsNeedingNewNSG.count -gt 0) {
                    # _GetVMNSG querys Azure Resource Graph, which may be delayed in returning results. Double-checking against network RP. Latency should improve in new ARG releases, so this may not be necessary in the future.
                    ForEach ($nicId in $nicsNeedingNewNSG) {
                        $nic = Get-AzNetworkInterface -ResourceId $nicId

                        # check for NSG on NIC
                        If ([string]::IsNullOrEmpty($nic.NetworkSecurityGroup)) {
                            $subnetConfig = Get-AzVirtualNetworkSubnetConfig -ResourceId $nic.IpConfigurations.Subnet.Id

                            # if there is no NSG on NIC, check subnet
                            If ([string]::IsNullOrEmpty($subnetConfig.NetworkSecurityGroup)) {
                                log -Message "[ValidateMigration] The following VM NICs need new NSGs: $($nicsNeedingNewNSG)" -Severity Error
                                $validationResult.failedValidations += "The following VM NICs need new NSGs: $($nicsNeedingNewNSG)"
                            }
                        }
                    }
                }
                Else {
                    log -Message "[ValidateMigration] All VM NICs have NSGs" -Severity Information
                    $validationResult.passedValidations += "All VM NICs have NSGs"
                }
            }
            'VMSS' {
                $vmsses = GetVmssFromBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer 

                ForEach ($vmss in $vmsses) {
                    $vmssHasNSG = _GetVMSSNSG -vmss $vmss -skipLogging

                    If (!$vmssHasNSG) {
                        log -Message "[ValidateMigration] VMSS '$($vmss.Name)' does not have an NSG" -Severity Error
                        $validationResult.failedValidations += "VMSS '$($vmss.Name)' does not have an NSG"
                    }
                    Else {
                        log -Message "[ValidateMigration] VMSS '$($vmss.Name)' has an NSG" -Severity Information
                        $validationResult.passedValidations += "VMSS '$($vmss.Name)' has an NSG"
                    }
                }
            }
        }
    }
    Else {
        log -Message "[ValidateMigration] Skipping NSG validation for internal load balancer" -Severity Information
        $validationResult.passedValidations += "Skipped NSG validation for internal load balancer"
    }

    # return object with validation status - useful for testing and scale migrations
    If ($OutputMigrationValiationObj) {
        return $validationResult
    }
}