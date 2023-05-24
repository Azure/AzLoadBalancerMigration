# ensure test environments meet requirements

BeforeAll {
    Function GetVMPIPAssociationsAndNICs {
        param ($VM)
        ## get NICs with public IPs attached
        $vmNICs = $VM.NetworkProfile.NetworkInterfaces | Get-AzResource | Get-AzNetworkInterface | Where-Object { $_.IpConfigurations.PublicIPAddress }

        ## build ipconfig/public IP table
        $publicIPIDs = @()
        $publicIPIPConfigAssociations = @()
        ForEach ($ipConfig in $vmNICs.IpConfigurations) {
            If ($ipConfig.PublicIPAddress) {
                $publicIPIDs += $ipConfig.PublicIPAddress.id
                $publicIPIPConfigAssociations += @{
                    publicIPId      = $ipConfig.PublicIPAddress.id
                    ipConfig        = $ipConfig
                    publicIP        = ''
                    publicIPAddress = ''
                }
            }
        }

        return ,$vmNICs, $publicIPIDs, $publicIPIPConfigAssociations
    }
}
Describe "Validate Migration Script Results" {
    Context 'Validate Scenario - 001-vms-single-nic-pip' -Tag 1 {
        BeforeAll {
            $rgName = '001-vms-single-nic-pip'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vm = $(Get-AzVm -ResourceGroup $rg.ResourceGroupName)
            $publicIp = Get-AzPublicIP -ResourceGroupName $rgName

            $vmNICs, $publicIPIDs, $publicIPIPConfigAssociations = GetVMPIPAssociationsAndNICs -vm $vm
        }

        It "VM should have 1 public IP associated" {   
            $publicIPIPConfigAssociations.Count | Should -BeExactly 1
        }

        It "Public IP address should be Standard SKU" { 
            $publicIp.Sku.Name | Should -Be 'Standard'
        }

        It "Public IP allocation method should be 'static'" {   
            $publicIp.PublicIPAllocationMethod | Should -Be 'Static'
        }
    }

    Context 'Validate Scenario - 002-vms-pip-no-nsg' -Tag 2 {
        BeforeAll {
            $rgName = '002-vms-pip-no-nsg'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vm = $(Get-AzVm -ResourceGroup $rg.ResourceGroupName)
            $publicIp = Get-AzPublicIP -ResourceGroupName $rgName

            $vmNICs, $publicIPIDs, $publicIPIPConfigAssociations = GetVMPIPAssociationsAndNICs -vm $vm
        }

        # migration should be skipped!
        It "VM should have 1 public IP associated" {   
            $publicIPIPConfigAssociations.Count | Should -BeExactly 1
        }

        It "Public IP address should be Standard SKU" { 
            $publicIp.Sku.Name | Should -Be 'Basic'
        }
    }

    Context 'Validate Scenario - 003-vms-nsg-subnet' -Tag 3 {
        BeforeAll {
            $rgName = '003-vms-nsg-subnet'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vm = $(Get-AzVm -ResourceGroup $rg.ResourceGroupName)
            $publicIp = Get-AzPublicIP -ResourceGroupName $rgName

            $vmNICs, $publicIPIDs, $publicIPIPConfigAssociations = GetVMPIPAssociationsAndNICs -vm $vm
        }

        It "VM should have 1 public IP associated" {   
            $publicIPIPConfigAssociations.Count | Should -BeExactly 1
        }

        It "Public IP address should be Standard SKU" { 
            $publicIp.Sku.Name | Should -Be 'Standard'
        }

        It "Public IP allocation method should be 'static'" {   
            $publicIp.PublicIPAllocationMethod | Should -Be 'Static'
        }
    }

    Context '004-vms-multi-nic-mix-nsg' -Tag 4 {
        BeforeAll {
            $rgName = '004-vms-multi-nic-mix-nsg'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vm = $(Get-AzVm -ResourceGroup $rg.ResourceGroupName)
            $publicIp = Get-AzPublicIP -ResourceGroupName $rgName

            $vmNICs, $publicIPIDs, $publicIPIPConfigAssociations = GetVMPIPAssociationsAndNICs -vm $vm
        }

            It "VM should have 1 public IP associated" {   
                $publicIPIPConfigAssociations.Count | Should -BeExactly 3
            }
    
            It "Public IP address should be Standard SKU" { 
                $publicIp.Sku.Name | Should -Be 'Standard'
            }
    
            It "Public IP allocation method should be 'static'" {   
                $publicIp.PublicIPAllocationMethod | Should -Be 'Static'
            }
    }

    Context '005-vms-multi-nic-nsg-on-private' -Tag 5 {
        BeforeAll {
            $rgName = '005-vms-multi-nic-nsg-on-private'
            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            $vm = $(Get-AzVm -ResourceGroup $rg.ResourceGroupName)
            $publicIp = Get-AzPublicIP -ResourceGroupName $rgName

            $vmNICs, $publicIPIDs, $publicIPIPConfigAssociations = GetVMPIPAssociationsAndNICs -vm $vm
        }

        # migration should be skipped!
        It "VM should have 1 public IP associated" {   
            $publicIPIPConfigAssociations.Count | Should -BeExactly 1
        }

        It "Public IP address should be Standard SKU" { 
            $publicIp.Sku.Name | Should -Be 'Basic'
        }
    }
} 
