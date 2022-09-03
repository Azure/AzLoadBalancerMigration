# ensure test environments meet requirements
<#
    001-basic-lb-int-single-fe.bicep
    002-basic-lb-int-multi-fe.bicep
    003-basic-lb-ext-single-fe.bicep
    004-basic-lb-ext-multi-fe.bicep
    005-basic-lb-int-single-be.bicep
    006-basic-lb-int-multi-be.bicep
    007-basic-lb-int-nat-rule.bicep
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

Describe "Validate Upgrade Script Results" {
    Context 'Validate Scenario - 001-basic-lb-int-single-fe' {
        BeforeAll {
            $rgName = 'rg-001-basic-lb-int-single-fe'
            $vmss = $(Get-AzVmss -ResourceGroup $rgName)
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

        It "Load Balancer has a single Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "VMSS has a single LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | Should -BeExactly 1
        }
    }

    Context 'Validate Scenario - 002-basic-lb-int-multi-fe' {
        BeforeAll {
            $rgName = 'rg-002-basic-lb-int-multi-fe'
            $vmss = $(Get-AzVmss -ResourceGroup $rgName)
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

        It "Load Balancer has a single Probe" {   
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
            $vmss = $(Get-AzVmss -ResourceGroup $rgName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
        }

        It "Load Balancer has a Standard LoadBalancer" {   
            $lb.SKU.Name | Should -Be 'Standard'
        }

        It "Load Balancer has a PrivateIpAddress" {   
            IsPrivateAddress($lb.FrontendIpConfigurations.PrivateIpAddress) | Should -Be $true
        }

        It "Load Balancer has a single FrontendIpConfiguration" {   
            $lb.FrontendIpConfigurations.Count | Should -BeExactly 1
        }

        It "Load Balancer has a single LoadBalancingRule" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 1
        }

        It "Load Balancer has a single Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "VMSS has a single LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | Should -BeExactly 1
        }
    }

    Context '004-basic-lb-ext-multi-fe' {
        BeforeAll {
            $rgName = 'rg-004-basic-lb-ext-multi-fe'
            $vmss = $(Get-AzVmss -ResourceGroup $rgName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
        }

        It "Load Balancer has a Standard LoadBalancer" {   
            $lb.SKU.Name | Should -Be 'Standard'
        }

        It "Load Balancer FrontendIpConfiguration 0 has a Public Ip Address" {   
            IsPrivateAddress($lb.FrontendIpConfigurations[0].PublicIpAddress) | Should -Be $false
        }

        It "Load Balancer FrontendIpConfiguration 1 has a Public Ip Address" {   
            IsPrivateAddress($lb.FrontendIpConfigurations[1].PublicIpAddress) | Should -Be $false
        }

        It "Load Balancer has 2 FrontendConfigurations" {   
            $lb.FrontendIpConfigurations.Count | Should -BeExactly 2
        }

        It "Load Balancer has 2 LoadBalancingRules" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 2
        }

        It "Load Balancer has a single Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "VMSS has a single LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
            Should -BeExactly 1
        }
    }

    Context '005-basic-lb-int-single-be' {
        BeforeAll {
            $rgName = 'rg-005-basic-lb-int-single-be'
            $vmss = $(Get-AzVmss -ResourceGroup $rgName)
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
            IsPrivateAddress($lb.FrontendIpConfigurations.PrivateIpAddress) | Should -Be $true
        }

        It "Load Balancer has 1 LoadBalancingRule" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 1
        }

        It "Load Balancer has a single Probe" {   
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
            $vmss = $(Get-AzVmss -ResourceGroup $rgName)
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

        It "Load Balancer has a single Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "VMSS has a 2 LoadBalancer BackendAddress Pools" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
            Should -BeExactly 2
        }
    }

    Context '007-basic-lb-int-nat-rule' {
        BeforeAll {
            $rgName = 'rg-007-basic-lb-int-nat-rule'
            $vmss = $(Get-AzVmss -ResourceGroup $rgName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
        }

        It "Load Balancer has a Standard LoadBalancer" {   
            $lb.SKU.Name | Should -Be 'Standard'
        }

        It "Load Balancer has 1 FrontendConfiguration" {   
            $lb.FrontendIpConfigurations.Count | Should -BeExactly 1
        }

        It "Load Balancer FrontendConfiguration has a PrivateIpAddress" {   
            IsPrivateAddress($lb.FrontendIpConfigurations.PrivateIpAddress) | Should -Be $true
        }

        It "Load Balancer has 1 LoadBalancingRule" {   
            $lb.LoadBalancingRules.Count | Should -BeExactly 1
        }

        It "Load Balancer has 2 BackendAddressPools" {
            $lb.BackendAddressPools.Count | Should -BeExactly 1
        }

        It "Load Balancer has 1 Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "Load Balancer has 1 inbound Nat rule" {
            $lb.InboundNatRules.Count | Should -BeExactly 1
        }

        It "VMSS has 1 LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
            Should -BeExactly 1
        }
    }

    Context '007-basic-lb-int-nat-rule' {
        BeforeAll {
            $rgName = 'rg-007-basic-lb-int-nat-rule'
            $vmss = $(Get-AzVmss -ResourceGroup $rgName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
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

        It "Load Balancer has 1 BackendAddressPools" {
            $lb.BackendAddressPools.Count | Should -BeExactly 1
        }

        It "Load Balancer has 1 Probe" {   
            $lb.Probes.Count | Should -Be 1
        }

        It "Load Balancer has 1 inbound Nat rule" {
            $lb.InboundNatRules.Count | Should -BeExactly 1
        }

        It "VMSS has 1 LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
            Should -BeExactly 1
        }
    }

    Context '008-basic-lb-int-nat-pool' {
        BeforeAll {
            $rgName = 'rg-008-basic-lb-int-nat-pool'
            $vmss = $(Get-AzVmss -ResourceGroup $rgName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
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

        It "Load Balancer has 1 inbound Nat Pool" {
            $lb.InboundNatPools.Count | Should -BeExactly 1
        }

        It "VMSS has 1 LoadBalancer BackendAddress Pool" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
            Should -BeExactly 1
        }
    }

    Context '009-basic-lb-ext-basic-static-pip' {
        BeforeAll {
            $rgName = 'rg-009-basic-lb-ext-basic-static-pip'
            $vmss = $(Get-AzVmss -ResourceGroup $rgName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
            $pip = $(Get-AzResource -ResourceID $lb.FrontendIpConfigurations[0].PublicIpAddress.id | Get-AzPublicIpAddress)
        }

        It "Load Balancer has a Standard LoadBalancer" {   
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

        It "Public Ip has a Standard SKu" {
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
        BeforeAll {
            $rgName = 'rg-012-basic-lb-ext-ipv6-fe'
            $vmss = $(Get-AzVmss -ResourceGroup $rgName)
            $lbName = ($vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Id).Split("/")[-3]
            $lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $lbName
            $pip1 = $(Get-AzResource -ResourceID $lb.FrontendIpConfigurations[0].PublicIpAddress.id | Get-AzPublicIpAddress)
            $pip2 = $(Get-AzResource -ResourceID $lb.FrontendIpConfigurations[1].PublicIpAddress.id | Get-AzPublicIpAddress)
        }

        It "Load Balancer has a Standard LoadBalancer" {   
            $lb.SKU.Name | Should -Be 'Standard'
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

        It "Public Ip has a Standard SKu" {
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

    Context '013-vmss-multi-be-single-lb' {
        BeforeAll {
            $rgName = 'rg-013-vmss-multi-be-single-lb'
            $vmss = $(Get-AzVmss -ResourceGroup $rgName)
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

        It "VMSS has 2 LoadBalancer BackendAddress Pools" {   
            $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
            Should -BeExactly 2
        }
    }

    Context '014-vmss-multi-be-multi-lb' {
        BeforeAll {
            $rgName = 'rg-014-vmss-multi-be-multi-lb'
            $vmss = $(Get-AzVmss -ResourceGroup $rgName)
            $lbs = $vmss.virtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations.IpConfigurations.LoadBalancerBackendAddressPools | ForEach-Object {$($_.Id).Split("/")[-3]} | Foreach-Object {Get-AzLoadBalancer -ResourceGroupName $rgName -Name $_}
            $lbInt = $lbs | Where-Object {$null -ne $_.FrontendIpConfigurations[0].PrivateIpAddress}
            $lbExt = $lbs | Where-Object {$null -eq $_.FrontendIpConfigurations[0].PrivateIpAddress}
            $pip = $(Get-AzResource -ResourceID $lbExt.FrontendIpConfigurations[0].PublicIpAddress.id | Get-AzPublicIpAddress)
        }

        It "Internal Load Balancer has a Standard SU" {   
            $lbInt.SKU.Name | Should -Be 'Standard'
        }

        It "Internal Load Balancer has 1 FrontendConfiguration" {   
            $lbInt.FrontendIpConfigurations.Count | Should -BeExactly 1
        }

        It "Internal Load Balancer FrontendConfiguration has a Private Ip Address" { 
            
            IsPrivateAddress($lbInt.FrontendIpConfigurations[0].PrivateIpAddress) | Should -Be $true
        }

        It "Internal Load Balancer has 1 LoadBalancing Rule" {   
            $lbInt.LoadBalancingRules.Count | Should -BeExactly 2
        }

        It "Internal Load Balancer has 1 Probe" {   
            $lbInt.Probes.Count | Should -Be 1
        }

        It "External Load Balancer has a Standard SKU" {   
            $lbExt.SKU.Name | Should -Be 'Standard'
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
} 
