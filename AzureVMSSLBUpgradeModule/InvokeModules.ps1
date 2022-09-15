Remove-Module AzureVMSSLBUpgradeModule -force
Import-Module C:\Projects\VSProjects\VMSS-LoadBalander-MIgration\AzureVMSSLBUpgradeModule\AzureVMSSLBUpgradeModule.psd1 -Force

# External
#Start-AzBasicLoadBalancerUpgrade -ResourceGroupName basiclb -BasicLoadBalancerName basiclb-loadbalancer -StandardLoadBalancerName stdlb-loadbalancer
# Start-AzBasicLoadBalancerUpgrade -ResourceGroupName basiclb -BasicLoadBalancerName basiclb-loadbalancer
#Start-AzBasicLoadBalancerUpgrade -RestoreFromJsonFile State-BasicLB-LoadBalancer-basiclb-20220907T1752322840.json
#Start-AzBasicLoadBalancerUpgrade -ResourceGroupName "rg-009-basic-lb-ext-basic-static-pip" -BasicLoadBalancerName "lb-basic-01"

# Internal
#Start-AzBasicLoadBalancerUpgrade -ResourceGroupName BasicLBInternal -BasicLoadBalancerName BasicLBInternal-LoadBalancer
Start-AzBasicLoadBalancerUpgrade -ResourceGroupName rg-013-vmss-multi-be-single-lb -BasicLoadBalancerName lb-basic-01

# Test IPV6
# Start-AzBasicLoadBalancerUpgrade -ResourceGroupName rg-012-basic-lb-ext-ipv6-fe -BasicLoadBalancerName lb-basi-c01

# Test with piping the object
#$lb = Get-AzLoadBalancer -ResourceGroupName "rg-009-basic-lb-ext-basic-static-pip" -Name "lb-basic-01"
#$lb | Start-AzBasicLoadBalancerUpgrade

# Testing passing an object
#$lb = Get-AzLoadBalancer -ResourceGroupName "rg-009-basic-lb-ext-basic-static-pip" -Name "lb-basic-01"
#Start-AzBasicLoadBalancerUpgrade -BasicLoadBalancer $lb

#Start-AzBasicLoadBalancerUpgrade -ResourceGroupName basiclb2 -BasicLoadBalancerName basiclb2-loadbalancer -StandardLoadBalancerName stdlb2-loadbalancer

############################################
# Build test environment
# Remove-AzResourceGroup -Name rg-009-basic-lb-ext-basic-static-pip -Force
# cd testEnvs\scripts
#.\deploy.ps1 -Location CentralUS -KeyVaultResourceGroupName rg-vmsstestingconfig -ScenarioNumber 012
############################################

#############
# Test Matrix
#############

# Tested OK
#Start-AzBasicLoadBalancerUpgrade -ResourceGroupName rg-001-basic-lb-int-single-fe -BasicLoadBalancerName lb-basic-01
#Start-AzBasicLoadBalancerUpgrade -FailedMigrationRetryFilePath C:\Projects\VSProjects\VMSS-LoadBalander-MIgration\State-lb-basic-01-rg-001-basic-lb-int-single-fe-20220908T1530071833.json

# Tested OK
#Start-AzBasicLoadBalancerUpgrade -ResourceGroupName rg-002-basic-lb-int-multi-fe -BasicLoadBalancerName lb-basic-01

# Tested OK
#Start-AzBasicLoadBalancerUpgrade -ResourceGroupName rg-003-basic-lb-ext-single-fe -BasicLoadBalancerName lb-basic-01

# Tested OK
#Start-AzBasicLoadBalancerUpgrade -ResourceGroupName rg-004-basic-lb-ext-multi-fe -BasicLoadBalancerName lb-basic-01

# Tested OK
#Start-AzBasicLoadBalancerUpgrade -ResourceGroupName rg-005-basic-lb-int-single-be -BasicLoadBalancerName lb-basic-01

# Tested OK
#Start-AzBasicLoadBalancerUpgrade -ResourceGroupName rg-006-basic-lb-int-multi-be -BasicLoadBalancerName lb-basic-01

# Tested Failed error in the scenario - already fixed and waiting deployment
# This scenario is failing but I created it manualy without bicep and worked fine
# Carml is causing issue here in the natrule
#Start-AzBasicLoadBalancerUpgrade -ResourceGroupName rg-007-basic-lb-int-nat-rule -BasicLoadBalancerName lb-basic-01

# did not test yet
#Start-AzBasicLoadBalancerUpgrade -ResourceGroupName rg-009-basic-lb-ext-basic-static-pip -BasicLoadBalancerName lb-basic-01


#############
# End Test Matrix
#############


