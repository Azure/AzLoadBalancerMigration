Remove-Module AzureVMSSLBMigrationModule -force
Import-Module C:\Projects\VSProjects\VMSS-LoadBalander-MIgration\AzureVMSSLBMigrationModule\AzureVMSSLBMigrationModule.psd1 -Force

# External
#Start-AzBasicLoadBalancerMigration -ResourceGroupName basiclb -BasicLoadBalancerName basiclb-loadbalancer -StandardLoadBalancerName stdlb-loadbalancer
# Start-AzBasicLoadBalancerMigration -ResourceGroupName basiclb -BasicLoadBalancerName basiclb-loadbalancer
#Start-AzBasicLoadBalancerMigration -RestoreFromJsonFile State-BasicLB-LoadBalancer-basiclb-20220907T1752322840.json
#Start-AzBasicLoadBalancerMigration -ResourceGroupName "rg-009-basic-lb-ext-basic-static-pip" -BasicLoadBalancerName "lb-basic-01"

# Internal
#Start-AzBasicLoadBalancerMigration -ResourceGroupName BasicLBInternal -BasicLoadBalancerName BasicLBInternal-LoadBalancer
#Start-AzBasicLoadBalancerMigration -ResourceGroupName rg-013-vmss-multi-be-single-lb -BasicLoadBalancerName lb-basic-01
# test different RG
#Start-AzBasicLoadBalancerMigration -ResourceGroupName rg-018-vmss-roll-upgrade-policy -BasicLoadBalancerName lb-basic-01

Start-AzBasicLoadBalancerMigration -FailedMigrationRetryFilePathLB C:\Projects\VSProjects\VMSS-LoadBalander-MIgration\State_lb-basic-01_rg-018-vmss-roll-upgrade-policy_20220919T0955511084.json -FailedMigrationRetryFilePathVMSS C:\Projects\VSProjects\VMSS-LoadBalander-MIgration\VMSS_vmss-01_rg-018-vmss-roll-upgrade-policy_20220919T0955511084.json

# Test IPV6
# Start-AzBasicLoadBalancerMigration -ResourceGroupName rg-012-basic-lb-ext-ipv6-fe -BasicLoadBalancerName lb-basi-c01

# Test with piping the object
#$lb = Get-AzLoadBalancer -ResourceGroupName "rg-009-basic-lb-ext-basic-static-pip" -Name "lb-basic-01"
#$lb | Start-AzBasicLoadBalancerMigration

# Testing passing an object
#$lb = Get-AzLoadBalancer -ResourceGroupName "rg-009-basic-lb-ext-basic-static-pip" -Name "lb-basic-01"
#Start-AzBasicLoadBalancerMigration -BasicLoadBalancer $lb

#Start-AzBasicLoadBalancerMigration -ResourceGroupName basiclb2 -BasicLoadBalancerName basiclb2-loadbalancer -StandardLoadBalancerName stdlb2-loadbalancer

############################################
# Build test environment
# Remove-AzResourceGroup -Name rg-018-vmss-roll-upgrade-policy -Force
# cd testEnvs\scripts
#.\deploy.ps1 -Location CentralUS -KeyVaultResourceGroupName rg-vmsstestingconfig -ScenarioNumber 018
# Deploy all scenarios
#.\deploy.ps1 -Location CentralUS -KeyVaultResourceGroupName rg-vmsstestingconfig
# Cleanup
# .\deploy.ps1 -Cleanup
############################################
# Remove-AzResourceGroup -Name rg-018-vmss-roll-upgrade-policy -Force;.\deploy.ps1 -Location CentralUS -KeyVaultResourceGroupName rg-vmsstestingconfig -ScenarioNumber 018