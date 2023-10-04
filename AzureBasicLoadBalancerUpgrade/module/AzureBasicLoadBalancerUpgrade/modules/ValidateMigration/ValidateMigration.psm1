Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/NsgCreation/NsgCreation.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/ValidateScenario/ValidateScenario.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/GetVmssFromBasicLoadBalancer/GetVmssFromBasicLoadBalancer.psd1")

Function ValidateMigration {
    param(
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $false)][string] $StandardLoadBalancerName,
        [Parameter(Mandatory = $false)][switch] $OutputMigrationValiationObj
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
    If ($standardLoadBalancer.BackendAddressPools.Count -ne $BasicLoadBalancer.BackendAddressPools.Count) {
        log -Message "[ValidateMigration] Standard Load Balancer does not have the same number of backend pools ('$($standardLoadBalancer.BackendAddressPools.Count)') as the Basic Load Balancer ('$($BasicLoadBalancer.BackendAddressPools.Count)')" -Severity Error
        $validationResult.failedValidations += "Standard Load Balancer does not have the same number of backend pools ('$($standardLoadBalancer.BackendAddressPools.Count)') as the Basic Load Balancer ('$($BasicLoadBalancer.BackendAddressPools.Count)')"
    }
    Else {
        log -Message "[ValidateMigration] Standard Load Balancer has the same number of backend pools ('$($standardLoadBalancer.BackendAddressPools.Count)') as the Basic Load Balancer ('$($BasicLoadBalancer.BackendAddressPools.Count)')" -Severity Information
        $validationResult.passedValidations += "Standard Load Balancer has the same number of backend pools ('$($standardLoadBalancer.BackendAddressPools.Count)') as the Basic Load Balancer ('$($BasicLoadBalancer.BackendAddressPools.Count)')"
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
    If ($standardLoadBalancer.InboundNatRules.Count -ne $BasicLoadBalancer.InboundNatRules.Count) {
        log -Message "[ValidateMigration] Standard Load Balancer does not have the same number of inbound NAT rules ('$($standardLoadBalancer.InboundNatRules.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatRules.Count)') " -Severity Error
        $validationResult.failedValidations += "Standard Load Balancer does not have the same number of inbound NAT rules ('$($standardLoadBalancer.InboundNatRules.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatRules.Count)')"
    }
    Else {
        log -Message "[ValidateMigration] Standard Load Balancer has the same number of inbound NAT rules ('$($standardLoadBalancer.InboundNatRules.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatRules.Count)') " -Severity Information
        $validationResult.passedValidations += "Standard Load Balancer has the same number of inbound NAT rules ('$($standardLoadBalancer.InboundNatRules.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatRules.Count)')"
    }

    # validate the standard load balancer has the same number of inbound NAT pools as the basic load balancer
    If ($standardLoadBalancer.InboundNatPools.Count -ne $BasicLoadBalancer.InboundNatPools.Count) {
        log -Message "[ValidateMigration] Standard Load Balancer does not have the same number of inbound NAT pools ('$($standardLoadBalancer.InboundNatPools.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatPools.Count)')" -Severity Error
        $validationResult.failedValidations += "Standard Load Balancer does not have the same number of inbound NAT pools ('$($standardLoadBalancer.InboundNatPools.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatPools.Count)')"
    }
    Else {
        log -Message "[ValidateMigration] Standard Load Balancer has the same number of inbound NAT pools ('$($standardLoadBalancer.InboundNatPools.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatPools.Count)')" -Severity Information
        $validationResult.passedValidations += "Standard Load Balancer has the same number of inbound NAT pools ('$($standardLoadBalancer.InboundNatPools.Count)') as the Basic Load Balancer ('$($basicLoadBalancer.InboundNatPools.Count)')"
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
                $vmssIDs = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object { ($_ -split '/virtualMachines/')[0].ToLower() } | Select-Object -Unique  

                ForEach ($vmssId in $vmssIds) {
                    $vmss = Get-AzResource -ResourceId $vmssId | Get-AzVmss

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