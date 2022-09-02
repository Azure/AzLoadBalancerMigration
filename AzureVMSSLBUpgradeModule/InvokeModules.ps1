Remove-Module AzureVMSSLBUpgradeModule -force
Import-Module C:\Projects\VSProjects\VMSS-LoadBalander-MIgration\AzureVMSSLBUpgradeModule\AzureVMSSLBUpgradeModule.psd1 -Force

AzureVMSSLBUpgrade -ResourceGroupName basiclb -BasicLoadBalancerName basiclb-loadbalancer -StandardLoadBalancerName stdlb-loadbalancer -FollowLog
#AzureVMSSLBUpgrade -ResourceGroupName "rg-009-basic-lb-ext-basic-static-pip" -BasicLoadBalancerName "lb-basic-01"

# Test with piping the object
#$lb = Get-AzLoadBalancer -ResourceGroupName "rg-009-basic-lb-ext-basic-static-pip" -Name "lb-basic-01"
#$lb | AzureVMSSLBUpgrade

# Testing passing an object
#$lb = Get-AzLoadBalancer -ResourceGroupName "rg-009-basic-lb-ext-basic-static-pip" -Name "lb-basic-01"
#AzureVMSSLBUpgrade -BasicLoadBalancer $lb

#AzureVMSSLBUpgrade -ResourceGroupName basiclb2 -BasicLoadBalancerName basiclb2-loadbalancer -StandardLoadBalancerName stdlb2-loadbalancer




# Build test environment
# Remove-AzResourceGroup -Name rg-009-basic-lb-ext-basic-static-pip -Force
# cd testEnvs\scripts
#.\deploy.ps1 -Location CentralUS -KeyVaultResourceGroupName rg-vmsstestingconfig -ScenarioNumber 012
