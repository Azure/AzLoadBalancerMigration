Remove-Module AzureBasicLoadBalancerMigration -force
Import-Module C:\Projects\VSProjects\AzLoadBalancerMigration\AzureBasicLoadBalancerMigration\AzureBasicLoadBalancerMigration.psd1 -Force

#Start-AzBasicLoadBalancerMigration -ResourceGroupName basiclb -BasicLoadBalancerName basiclb-loadbalancer -StandardLoadBalancerName stdlb-loadbalancer
#Start-AzBasicLoadBalancerMigration -ResourceGroupName "rg-009-basic-lb-ext-basic-static-pip" -BasicLoadBalancerName "lb-basic-01"
#Start-AzBasicLoadBalancerMigration -FailedMigrationRetryFilePathLB C:\Projects\VSProjects\AzLoadBalancerMigration\State_lb-basic-01_rg-018-vmss-roll-upgrade-policy_20220919T0955511084.json -FailedMigrationRetryFilePathVMSS C:\Projects\VSProjects\AzLoadBalancerMigration\VMSS_vmss-01_rg-018-vmss-roll-upgrade-policy_20220919T0955511084.json

#$lb = Get-AzLoadBalancer -ResourceGroupName "rg-009-basic-lb-ext-basic-static-pip" -Name "lb-basic-01"
#$lb | Start-AzBasicLoadBalancerMigration

############################################
# Build test environment
# Remove-AzResourceGroup -Name rg-018-vmss-roll-upgrade-policy -Force
# cd testEnvs\scripts
#.\deploy.ps1 -Location CentralUS -KeyVaultResourceGroupName rg-vmsstestingconfig -ScenarioNumber 018
# Deploy all scenarios
#.\deploy.ps1 -Location CentralUS -KeyVaultResourceGroupName rg-vmsstestingconfig
# Run all scenarios
# .\deploy.ps1 -RunMigration
# Cleanup
# .\deploy.ps1 -Cleanup
############################################