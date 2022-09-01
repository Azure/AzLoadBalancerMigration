Remove-Module AzureVMSSLBUpgradeModule -force
Import-Module C:\Projects\VSProjects\VMSS-LoadBalander-MIgration\AzureVMSSLBUpgradeModule\AzureVMSSLBUpgradeModule.psd1 -Force

AzureVMSSLBUpgrade -ResourceGroupName basiclb -BasicLoadBalancerName basiclb-loadbalancer -StdLoadBalancerName stdlb-loadbalancer
#AzureVMSSLBUpgrade -ResourceGroupName basiclb2 -BasicLoadBalancerName basiclb2-loadbalancer -StdLoadBalancerName stdlb2-loadbalancer

