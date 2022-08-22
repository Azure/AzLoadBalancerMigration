$location = 'australiaeast'
$keyVaultResourceGroupName = 'rg-vmsstestingconfig'

# deploy keyvault
New-AzDeployment -Name 'prereq-deployment' `
    -TemplateFile ./prereqs.bicep `
    -ResourceGroupName $keyVaultResourceGroupName `
    -Location $location

$keyVaultName = (
    Get-AzResourceGroupDeployment `
        -Name 'keyvault-deployment' `
        -ResourceGroupName $keyVaultResourceGroupName `
).Outputs.name.value

# deploy scenarios
$templates = Get-ChildItem -Path ../scenarios -Filter *.bicep
$jobs = @()

foreach ($template in $templates) {
    $jobs = New-AzDeployment `
        -Name $template.Name `
        -ResourceGroupName "rg-$($template.BaseName)" `
        -TemplateFile "./$($template.Name)" `
        -keyVaultName $keyVaultName `
        -location $location `
        -AsJob
}

$jobs | Wait-Job

# ensure test environments meet requirements
Describe "Verify basic load balancer & VM scale set initial state" {
    $loadBalancers = @()
    $vmScaleSets = @()

    foreach ($template in $templates) {
        $loadBalancers += $(Get-AzLoadBalancer -ResourceGroup "rg-$($template.BaseName)")
        $vmScaleSets += $(Get-AzVMSS -ResourceGroup "rg-$($template.BaseName)")
    }    

    Context "Basic Load Balancer" {

        foreach ($loadBalancer in $loadBalancers) {
            It "'$($loadBalancer.Name)' Should be Basic SKU" {
                $loadBalancer.Sku.Name | Should Be "Basic" 
            }
            
            It "'$($loadBalancer.Name)' Should have at least one load balancing rule" {
                $loadBalancer.LoadBalancingRules.Count | Should BeGreaterThan 0
            }

            It "'$($loadBalancer.Name)' Should have at least one probe" {
                $loadBalancer.Probes.Count | Should BeGreaterThan 0
            }

            It "'$($loadBalancer.Name)' Should have at least one frontend configuration" {
                $loadBalancer.FrontendIpConfigurations.Count | Should BeGreaterThan 0
            }

            It "'$($loadBalancer.Name)' Should have at least one backend address pool" {
                $loadBalancer.BackendAddressPools.Count | Should BeGreaterThan 0
            }
        }
    }

    Context "VM Scale Set" {
        foreach ($vmScaleSet in $vmScaleSets) {
            It "'$($vmScaleSet.Name)' Should have at least one associated load balancer backend address pool" {
                $vmScaleSet.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
                Should BeGreaterThan 0
            }
        }
    }
}
