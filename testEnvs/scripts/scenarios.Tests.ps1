# ensure test environments meet requirements
<#
    001-basic-lb-int-single-fe.bicep
    002-basic-lb-int-multi-fe.bicep
    003-basic-lb-ext-single-fe.bicep
    004-basic-lb-ext-multi-fe.bicep
    005-basic-lb-int-single-be.bicep
    006-basic-lb-int-multi-be.bicep
    008-basic-lb-nat-pool.bicep
    009-basic-lb-ext-basic-static-pip.bicep
    012-basic-lb-ext-ipv6-fe.bicep
    013-vmss-multi-be-single-lb.bicep
    014-vmss-multi-be-multi-lb.bicep
    016-vmss-automatic-upgrade-policy.bicep
    018-vmss-roll-upgrade-policy.bicep
    020-vmss-nsg-allows-lb-traffic.bicep
    021-vmss-nsg-no-allow-lb-traffic.bicep
    022-vmss-instance-protection_MANUALCONFIG.bicep
    023-vmss-high-instance-count_HIGHCOST.bicep
#>

Describe "Validate Migration Script Results" {
    BeforeAll {
        function IsPrivateAddress {
            Param
            (
                [string]$AddressString
            )
        
            $ErrorActionPreference = 'Stop'
            [ref]$ipRef = $null
        
            $result = [System.Net.IPAddress]::TryParse($AddressString, $ipRef)
            if (!$result) {
                return Write-Error -Exception "Error Parsing Ip Address $AddressString"
            }
        
            $ipBytes = $ipRef.Value.GetAddressBytes()
            switch ($ipBytes[0]) {
                10 { 
                    return $true
                }
                172 {
                    return $($ipBytes[1] -lt 32 -and $ipBytes[1] -ge 16)
                }
                192 {
                    return $ipBytes[1] -eq 168
                }
                default {
                    return $false
                }
            }
        }
    }
    Context 'Validate Scenario - 001-basic-lb-int-single-fe' {
        BeforeAll {
            $rgName = 'rg-001-basic-lb-int-single-fe'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vmss = $(Get-AzVmss -ResourceGroup $rg.ResourceGroupName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
        }

        It "Load Balancer has a Standard LoadBalancer" {   
            $lb.SKU.Name | Should -Be 'Standard'
        }

        It "Load Balancer FrontendIpConfiguration has a PrivateIpAddress" {   
            IsPrivateAddress($lb.FrontendIpConfigurations[0].PrivateIpAddress) | Should -Be $true
        }

        It "Load Balancer has a single FrontendIpConfiguration" {   
            $lb.FrontendIpConfigurations.Count | Should -BeExactly 1
        }

        It "Load Balancer has a single LoadBalancingRule" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 1
        }

        It "Load Balancer has 1 Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "VMSS has a single LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | Should -BeExactly 1
        }
    }

    Context 'Validate Scenario - 002-basic-lb-int-multi-fe' {
        BeforeAll {
            $rgName = 'rg-002-basic-lb-int-multi-fe'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vmss = $(Get-AzVmss -ResourceGroup $rg.ResourceGroupName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
        }

        It "Load Balancer has a Standard LoadBalancer" {   
            $lb.SKU.Name | Should -Be 'Standard'
        }

        It "Load Balancer FrontendIpConfiguration 0 has a PrivateIpAddress" {   
            IsPrivateAddress($lb.FrontendIpConfigurations[0].PrivateIpAddress) | Should -Be $true
        }

        It "Load Balancer FrontendIpConfiguration 1 has a PrivateIpAddress" {   
            IsPrivateAddress($lb.FrontendIpConfigurations[1].PrivateIpAddress) | Should -Be $true
        }

        It "Load Balancer has 2 FrontendIpConfigurations" {   
            $lb.FrontendIpConfigurations.Count | Should -Be 2
        }

        It "Load Balancer has 2 LoadBalancingRules" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 2
        }

        It "Load Balancer has 1 Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "VMSS has a single LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
            Should -BeExactly 1
        }
    }

    Context 'Validate Scenario - 003-basic-lb-ext-single-fe' {
        BeforeAll {
            $rgName = 'rg-003-basic-lb-ext-single-fe'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vmss = $(Get-AzVmss -ResourceGroup $rg.ResourceGroupName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
            $nsg = Get-AzResource -ResourceId $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].NetworkSecurityGroup.Id | Get-AzNetworkSecurityGroup
        }

        It "Load Balancer has a Standard LoadBalancer" {   
            $lb.SKU.Name | Should -Be 'Standard'
        }

        It "Load Balancer has a Public IpAddress" {   
            IsPrivateAddress((Get-AzResource -ResourceId $lb.FrontendIpConfigurations.PublicIpAddress.Id | Get-AzPublicIpAddress).IpAddress) | Should -Be $false
        }

        It "Load Balancer has a single FrontendIpConfiguration" {   
            $lb.FrontendIpConfigurations.Count | Should -BeExactly 1
        }

        It "Load Balancer has a single LoadBalancingRule" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 1
        }

        It "Load Balancer has 1 Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "VMSS has a single LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | Should -BeExactly 1
        }

        It "VMSS NIC has a Network Security Group" {
            $nsg.SecurityRules.Count | Should -Be 1
        }

        It "Network Security Group has an inbound allow rule for port 80" {
            ($nsg.SecurityRules[0].DestinationPortRange -eq 80 -and $nsg.SecurityRules[0].Access -eq 'Allow') | Should -be $true
        }
    }

    Context '004-basic-lb-ext-multi-fe' {
        BeforeAll {
            $rgName = 'rg-004-basic-lb-ext-multi-fe'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vmss = $(Get-AzVmss -ResourceGroup $rg.ResourceGroupName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
        }

        It "Load Balancer has a Standard LoadBalancer" {   
            $lb.SKU.Name | Should -Be 'Standard'
        }

        It "Load Balancer has a Public IpAddress" {   
            IsPrivateAddress((Get-AzResource -ResourceId $lb.FrontendIpConfigurations[0].PublicIpAddress.Id | Get-AzPublicIpAddress).IpAddress) | Should -Be $false
        }

        It "Load Balancer has a Public IpAddress" {   
            IsPrivateAddress((Get-AzResource -ResourceId $lb.FrontendIpConfigurations[1].PublicIpAddress.Id | Get-AzPublicIpAddress).IpAddress) | Should -Be $false
        }

        It "Load Balancer has 2 FrontendConfigurations" {   
            $lb.FrontendIpConfigurations.Count | Should -BeExactly 2
        }

        It "Load Balancer has 2 LoadBalancingRules" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 2
        }

        It "Load Balancer has 2 Probes" {   
            $lb.Probes.Count | Should -Be 2
        }

        It "VMSS has a single LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations.LoadBalancerBackendAddressPools.Count | 
            Should -BeExactly 1
        }
    }

    Context '005-basic-lb-int-single-be' {
        BeforeAll {
            $rgName = 'rg-005-basic-lb-int-single-be'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vmss = $(Get-AzVmss -ResourceGroup $rg.ResourceGroupName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
        }

        It "Load Balancer has a Standard LoadBalancer" {   
            $lb.SKU.Name | Should -Be 'Standard'
        }

        It "Load Balancer has 1 FrontendIpConfiguration" {   
            $lb.FrontendIpConfigurations.Count | Should -BeExactly 1
        }

        It "Load Balancer FrontendIpConfiguration has a PrivateIpAddress" {   
            IsPrivateAddress($lb.FrontendIpConfigurations[0].PrivateIpAddress) | Should -Be $true
        }

        It "Load Balancer has 1 LoadBalancingRule" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 1
        }

        It "Load Balancer has 1 Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "VMSS has a single LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
            Should -BeExactly 1
        }
    }

    Context '006-basic-lb-int-multiple-be' {
        BeforeAll {
            $rgName = 'rg-006-basic-lb-int-multi-be'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vmss = $(Get-AzVmss -ResourceGroup $rg.ResourceGroupName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
        }

        It "Load Balancer has a Standard LoadBalancer" {   
            $lb.SKU.Name | Should -Be 'Standard'
        }

        It "Load Balancer has 1 FrontendIpConfiguration" {   
            $lb.FrontendIpConfigurations.Count | Should -BeExactly 1
        }

        It "Load Balancer FrontendIpConfiguration has a PrivateIpAddress" {   
            IsPrivateAddress($lb.FrontendIpConfigurations[0].PrivateIpAddress) | Should -Be $true
        }

        It "Load Balancer has 2 BackendAddressPools" {
            $lb.BackendAddressPools.Count | Should -BeExactly 2
        }

        It "Load Balancer has 1 LoadBalancingRule" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 1
        }

        It "Load Balancer has 1 Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "VMSS nic has 1 LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
            Should -BeExactly 1
        }
    }

    Context '008-basic-lb-nat-pool' {
        BeforeAll {
            $rgName = 'rg-008-basic-lb-nat-pool'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vmss = $(Get-AzVmss -ResourceGroup $rg.ResourceGroupName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
            $nic1IpConfig1 = $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations | 
                where-object {$_.name -eq 'vmss-01-nic-01'} | 
                Select-Object -ExpandProperty IpConfigurations |
                Where-Object {$_.name -eq 'ipconfig1'}
            $nic1IpConfig2 = $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations | 
                where-object {$_.name -eq 'vmss-01-nic-01'} | 
                Select-Object -ExpandProperty IpConfigurations |
                Where-Object {$_.name -eq 'ipconfig2'}
            $nic2IpConfig1 = $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations | 
                where-object {$_.name -eq 'vmss-01-nic-02'} | 
                Select-Object -ExpandProperty IpConfigurations |
                Where-Object {$_.name -eq 'ipconfig1'}
            $nic2IpConfig2 = $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations | 
                where-object {$_.name -eq 'vmss-01-nic-02'} | 
                Select-Object -ExpandProperty IpConfigurations |
                Where-Object {$_.name -eq 'ipconfig2'}
        }

        It "Load Balancer has a Standard LoadBalancer" {   
            $lb.SKU.Name | Should -Be 'Standard'
        }

        It "Load Balancer has 1 FrontendConfiguration" {   
            $lb.FrontendIpConfigurations.Count | Should -BeExactly 1
        }

        It "Load Balancer FrontendConfiguration has a Private Ip Address" {   
            IsPrivateAddress($lb.FrontendIpConfigurations.PrivateIpAddress) | Should -Be $true
        }

        It "Load Balancer has 1 LoadBalancingRule" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 1
        }

        It "Load Balancer has 1 Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "Load Balancer has 3 inbound Nat Pools" {
            $lb.InboundNatPools.Count | Should -BeExactly 3
        }

        It "VMSS Nic 1 IP config 1 should be associated with 1 nat pool" {
            $nic1IpConfig1.LoadBalancerInboundNatPools.Count | Should -BeExactly 1
        }

        It "VMSS NIC 1 ipconfig 1 should be assocated with NAT Pool 1" {
            $nic1IpConfig1.LoadBalancerInboundNatPools[0].Name | Should -Be 'natpool-01'
        }

        It "VMSS Nic 1 ipconfig 1 should be associated with one backend address pool" {
            $nic1IpConfig1.LoadBalancerBackendAddressPools.Count | Should -BeExactly 1
        }

        It "VMSS Nic 1 IP config 2 should be associated with 1 nat pool" {
            $nic1IpConfig2.LoadBalancerInboundNatPools.Count | Should -BeExactly 1
        }

        It "VMSS NIC 1 ipconfig 2 should be assocated with NAT Pool 2" {
            $nic1IpConfig2.LoadBalancerInboundNatPools[0].Name | Should -Be 'natpool-02'
        }

        It "vmss nic 2 ipconfig 1 should be associated with 1 nat pool" {
            $nic2IpConfig1.LoadBalancerInboundNatPools.Count | Should -BeExactly 1
        }

        It "VMSS NIC 2 ipconfig 1 should be assocated with NAT Pool 3" {
            $nic2IpConfig1.LoadBalancerInboundNatPools[0].Name | Should -Be 'natpool-03'
        }

        It "VMSS Nic 2 IP config 2 should be associated with no nat pool" {
            $nic2IpConfig2.LoadBalancerInboundNatPools.Count | Should -BeExactly 0
        }

        It "VMSS has 1 LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
            Should -BeExactly 1
        }

        It "LB has 3 nat rules (auto-generated for nat pool)" {
            $lb.InboundNatRules.Count | Should -BeExactly 3
        }
    }

    Context '009-basic-lb-ext-basic-static-pip' {
        BeforeAll {
            $rgName = 'rg-009-basic-lb-ext-basic-static-pip'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vmss = $(Get-AzVmss -ResourceGroup $rg.ResourceGroupName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
            $pip = $(Get-AzResource -ResourceID $lb.FrontendIpConfigurations[0].PublicIpAddress.id | Get-AzPublicIpAddress)
        }

        It "Load Balancer has a Standard Sku" {   
            $lb.SKU.Name | Should -Be 'Standard'
        }

        It "Load Balancer has 1 FrontendConfiguration" {   
            $lb.FrontendIpConfigurations.Count | Should -BeExactly 1
        }

        It "Load Balancer FrontendConfiguration has a Public Ip Address" {  
            IsPrivateAddress($pip.IpAddress) | Should -Be $false
        }

        It "Load Balancer has 1 LoadBalancingRule" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 1
        }

        It "Public Ip has a Static Address" {
            $pip.PublicIpAllocationMethod | Should -Be 'Static'
        }

        It "Public Ip has a Standard Sku" {
            $pip.Sku.Name | Should -Be 'Standard'
        }

        It "Load Balancer has 1 Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "VMSS has 1 LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
            Should -BeExactly 1
        }
    }

    Context '012-basic-lb-ext-ipv6-fe' {
        # migration should fail!
        BeforeAll {
            $rgName = 'rg-012-basic-lb-ext-ipv6-fe'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vmss = $(Get-AzVmss -ResourceGroup $rg.ResourceGroupName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
            $pip1 = $(Get-AzResource -ResourceID $lb.FrontendIpConfigurations[0].PublicIpAddress.id | Get-AzPublicIpAddress)
            $pip2 = $(Get-AzResource -ResourceID $lb.FrontendIpConfigurations[1].PublicIpAddress.id | Get-AzPublicIpAddress)
        }

        It "Load Balancer has a Basic LoadBalancer" {   
            $lb.SKU.Name | Should -Be 'Basic'
        }

        It "Load Balancer has 2 FrontendConfigurations" {   
            $lb.FrontendIpConfigurations.Count | Should -BeExactly 2
        }

        It "Load Balancer FrontendConfiguration [0] has a Public Ip Addresses" { 
            IsPrivateAddress($pip1.IpAddress) | Should -Be $false
        }

        It "Load Balancer FrontendConfiguration [1] has a Public Ip Addresses" {  
            IsPrivateAddress($pip2.IpAddress) | Should -Be $false
        }

        It "Public Ip Address [0] has version 'IPv4'" {  
            $pip1.PublicIpAddressVersion | Should -Be 'IPv4'
        }

        It "Public Ip Address [1] has version 'IPv6'" {  
            $pip2.PublicIpAddressVersion | Should -Be 'IPv6'
        }

        It "Load Balancer has 1 LoadBalancingRule" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 1
        }

        It "Public Ip has a Static Address" {
            $pip.PublicIpAllocationMethod | Should -Be 'Static'
        }

        It "Public Ip has a Basic SKu" {
            $pip.Sku.Name | Should -Be 'Basic'
        }

        It "Load Balancer has 1 Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "VMSS has 1 LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
            Should -BeExactly 1
        }
    }

    Context '013-vmss-multi-be-single-lb' {
        BeforeAll {
            $rgName = 'rg-013-vmss-multi-be-single-lb'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vmss = $(Get-AzVmss -ResourceGroup $rg.ResourceGroupName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
        }

        It "Load Balancer has a Standard LoadBalancer" {   
            $lb.SKU.Name | Should -Be 'Standard'
        }

        It "Load Balancer has 1 FrontendConfiguration" {   
            $lb.FrontendIpConfigurations.Count | Should -BeExactly 1
        }

        It "Load Balancer FrontendConfiguration has a Private Ip Addresses" { 
            IsPrivateAddress($lb.FrontendIpConfigurations[0].PrivateIpAddress) | Should -Be $true
        }

        It "Load Balancer has 1 LoadBalancing Rule" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 2
        }

        It "Load Balancer has 1 Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "LoadBalancer has 2 BackendPools" {
            $lb.BackendAddressPools.Count | Should -BeExactly 2
        }

        It "VMSS nic has 1 LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
            Should -BeExactly 1
        }
    }

    Context '014-vmss-multi-be-multi-lb' {
        #migration should fail!
        BeforeAll {
            $rgName = 'rg-014-vmss-multi-be-multi-lb'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vmss = $(Get-AzVmss -ResourceGroup $rg.ResourceGroupName)
            $lbs = $(Get-AzLoadBalancer -ResourceGroup $rg.ResourceGroupName)
            $lbs = $vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations.IpConfigurations.LoadBalancerBackendAddressPools | ForEach-Object { $($_.Id).Split("/")[-3] } | Foreach-Object { Get-AzLoadBalancer -ResourceGroupName $rgName -Name $_ }
            $lbInt = $lbs | Where-Object { $null -ne $_.FrontendIpConfigurations[0].PrivateIpAddress }
            $lbExt = $lbs | Where-Object { $null -eq $_.FrontendIpConfigurations[0].PrivateIpAddress }
            $pip = $(Get-AzResource -ResourceID $lbExt.FrontendIpConfigurations[0].PublicIpAddress.id -ErrorAction Stop | Get-AzPublicIpAddress)
        }

        It "Internal Load Balancer has a Basic SU" {   
            $lbInt.SKU.Name | Should -Be 'Basic'
        }

        It "Internal Load Balancer has 1 FrontendConfiguration" {   
            $lbs[0].FrontendIpConfigurations.Count | Should -BeExactly 1
        }

        It "Internal Load Balancer FrontendConfiguration has a Private Ip Address" { 
            
            IsPrivateAddress($lbs[0].FrontendIpConfigurations[0].PrivateIpAddress) | Should -Be $true
        }

        It "Internal Load Balancer has 1 LoadBalancing Rule" {   
            $lbInt.LoadBalancingRules.Count | Should -BeExactly 2
        }

        It "Internal Load Balancer has 1 Probe" {   
            $lbInt.Probes.Count | Should -Be 1
        }

        It "External Load Balancer has a Basic SKU" {   
            $lbExt.SKU.Name | Should -Be 'Basic'
        }

        It "External Load Balancer has 1 FrontendConfiguration" {   
            $lbExt.FrontendIpConfigurations.Count | Should -BeExactly 1
        }

        It "External Load Balancer FrontendConfiguration has a Public Ip Address" {
            $lbExt.FrontendIpConfigurations[0].PrivateIpAddress | Should -Be $null
        }

        It "VMSS has 2 LoadBalancer BackendAddress Pools" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
            Should -BeExactly 2
        }
    }

    Context '016-vmss-automatic-upgrade-policy' {
        BeforeAll {
            $rgName = 'rg-016-vmss-automatic-upgrade-policy'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vmss = $(Get-AzVmss -ResourceGroup $rg.ResourceGroupName)
            $lb = $vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations.IpConfigurations.LoadBalancerBackendAddressPools[0].Id.Split("/")[-3] | Foreach-Object { Get-AzLoadBalancer -ResourceGroupName $rgName -Name $_ }
            # $pip = $(Get-AzResource -ResourceID $lbExt.FrontendIpConfigurations[0].PublicIpAddress.id -ErrorAction Stop | Get-AzPublicIpAddress)
        }

        It "Internal Load Balancer has a Standard SU" {   
            $lb.SKU.Name | Should -Be 'Standard'
        }

        It "Internal Load Balancer has 1 FrontendConfiguration" {   
            $lb.FrontendIpConfigurations.Count | Should -BeExactly 1
        }

        It "Internal Load Balancer FrontendConfiguration has a Private Ip Address" { 
            
            IsPrivateAddress($lb[0].FrontendIpConfigurations[0].PrivateIpAddress) | Should -Be $true
        }

        It "Internal Load Balancer has 1 LoadBalancing Rule" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 1
        }

        It "Internal Load Balancer has 1 Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "VMSS has 2 LoadBalancer BackendAddress Pools" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | Should -BeExactly 1
        }
    }

    Context '017-vmss-multi-ipconfigs-multi-be' {
        BeforeAll {
            $rgName = '017-vmss-multi-ipconfigs-multi-be'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vmss = $(Get-AzVmss -ResourceGroup $rg.ResourceGroupName)
            $lb = $vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations.IpConfigurations.LoadBalancerBackendAddressPools[0].Id.Split("/")[-3] | Foreach-Object { Get-AzLoadBalancer -ResourceGroupName $rgName -Name $_ }
            # $pip = $(Get-AzResource -ResourceID $lbExt.FrontendIpConfigurations[0].PublicIpAddress.id -ErrorAction Stop | Get-AzPublicIpAddress)
            $nic1IpConfig1 = $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations | 
                where-object {$_.name -like '*-nic-01'} | 
                Select-Object -ExpandProperty IpConfigurations |
                Where-Object {$_.name -eq 'ipconfig1'}
            $nic1IpConfig2 = $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations | 
                where-object {$_.name -like '*-nic-01'} | 
                Select-Object -ExpandProperty IpConfigurations |
                Where-Object {$_.name -eq 'ipconfig2'}

        }

        It "Internal Load Balancer has a Standard SU" {   
            $lb.SKU.Name | Should -Be 'Standard'
        }

        It "Internal Load Balancer has 1 FrontendConfiguration" {   
            $lb.FrontendIpConfigurations.Count | Should -BeExactly 1
        }

        It "Internal Load Balancer FrontendConfiguration has a Private Ip Address" { 
            
            IsPrivateAddress($lb[0].FrontendIpConfigurations[0].PrivateIpAddress) | Should -Be $true
        }

        It "Internal Load Balancer has 2 LoadBalancing Rule" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 2
        }

        It "Internal Load Balancer has 1 Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "Internal load balancer has 2 backend pools" {
            $lb.BackendAddressPools.Count | Should -Be 2
        }

        It "VMSS has 2 LoadBalancer BackendAddress Pools" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | Should -BeExactly 1
        }

        It "VMSS nic 1 ipconfig 1 should belong to backend pool 1" {
            $nic1IpConfig1.LoadBalancerBackendAddressPools[0].Name | Should -Be 'be-01'
        }

        It "VMSS nic 1 ipconfig 2 should belong to backend pool 2" {
            $nic1IpConfig2.LoadBalancerBackendAddressPools[0].Name | Should -Be 'be-02'
        }
    }
} 
