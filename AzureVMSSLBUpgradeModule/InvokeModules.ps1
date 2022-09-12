Remove-Module AzureVMSSLBUpgradeModule -force
Import-Module C:\Projects\VSProjects\VMSS-LoadBalander-MIgration\AzureVMSSLBUpgradeModule\AzureVMSSLBUpgradeModule.psd1 -Force

# External
#Start-AzBasicLoadBalancerUpgrade -ResourceGroupName basiclb -BasicLoadBalancerName basiclb-loadbalancer -StandardLoadBalancerName stdlb-loadbalancer
# Start-AzBasicLoadBalancerUpgrade -ResourceGroupName basiclb -BasicLoadBalancerName basiclb-loadbalancer
#Start-AzBasicLoadBalancerUpgrade -RestoreFromJsonFile State-BasicLB-LoadBalancer-basiclb-20220907T1752322840.json
#Start-AzBasicLoadBalancerUpgrade -ResourceGroupName "rg-009-basic-lb-ext-basic-static-pip" -BasicLoadBalancerName "lb-basic-01"

# Internal
Start-AzBasicLoadBalancerUpgrade -ResourceGroupName BasicLBInternal -BasicLoadBalancerName BasicLBInternal-LoadBalancer

# Test IPV6
# Start-AzBasicLoadBalancerUpgrade -ResourceGroupName rg-012-basic-lb-ext-ipv6-fe -BasicLoadBalancerName lb-basi-c01

# Test with piping the object
#$lb = Get-AzLoadBalancer -ResourceGroupName "rg-009-basic-lb-ext-basic-static-pip" -Name "lb-basic-01"
#$lb | Start-AzBasicLoadBalancerUpgrade

# Testing passing an object
#$lb = Get-AzLoadBalancer -ResourceGroupName "rg-009-basic-lb-ext-basic-static-pip" -Name "lb-basic-01"
#Start-AzBasicLoadBalancerUpgrade -BasicLoadBalancer $lb

#Start-AzBasicLoadBalancerUpgrade -ResourceGroupName basiclb2 -BasicLoadBalancerName basiclb2-loadbalancer -StandardLoadBalancerName stdlb2-loadbalancer




# Build test environment
# Remove-AzResourceGroup -Name rg-009-basic-lb-ext-basic-static-pip -Force
# cd testEnvs\scripts
#.\deploy.ps1 -Location CentralUS -KeyVaultResourceGroupName rg-vmsstestingconfig -ScenarioNumber 012
