Param (
    [string]$Location = 'australiaeast',
    [string]$KeyVaultResourceGroupName = 'rg-vmsstestingconfig',
    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'

$templates = Get-ChildItem -Path ../scenarios -Filter *.bicep  -Exclude *MANUAL* -Recurse -Depth 0

# if '-Cleanup' switch is supplied, remove the resource groups and exit
if ($Cleanup -and $null -ne $templates) {
    $jobs = @()

    $templates | 
    Foreach-Object {
        "Removing Resource Group rg-$($_.BaseName)"
        $jobs += $(Remove-AzResourceGroup -Name "rg-$($_.BaseName)" -Force -AsJob)
    }

    $jobs | Wait-Job | Receive-Job
    return
}

# deploy keyvault
$params = @{
    Name                    = 'prereq-deployment'
    TemplateFile            = './prereqs.bicep'
    TemplateParameterObject = @{
        Location          = $Location
        ResourceGroupName = $keyVaultResourceGroupName
    }
}

New-AzSubscriptionDeployment -Location $location @params

$keyVaultName = (
    Get-AzResourceGroupDeployment `
        -Name 'keyvault-deployment' `
        -ResourceGroupName $keyVaultResourceGroupName `
).Outputs.name.value

# deploy scenarioset-
$jobs = @()

foreach ($template in $templates) {

    $params = @{
        Name                    = "vmss-lb-deployment-$((get-date).tofiletime())"
        TemplateFile            = $template.FullName
        TemplateParameterObject = @{
            Location                  = $Location
            ResourceGroupName         = "rg-$($template.BaseName)"
            KeyVaultName              = $keyVaultName
            KeyVaultResourceGroupName = $KeyVaultResourceGroupName
        }
    }

    $jobs += New-AzSubscriptionDeployment -Location $location @params -AsJob
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
            It "load balancer '$($loadBalancer.Name)' in resource group '$($loadBalancer.ResourceGroupName)' Should be Basic SKU" {
                $loadBalancer.Sku.Name | Should Be "Basic" 
            }
            
            It "load balancer '$($loadBalancer.Name)' in resource group '$($loadBalancer.ResourceGroupName)' Should have at least one load balancing rule" {
                $loadBalancer.LoadBalancingRules.Count | Should BeGreaterThan 0
            }

            It "load balancer '$($loadBalancer.Name)' in resource group '$($loadBalancer.ResourceGroupName)' Should have at least one probe" {
                $loadBalancer.Probes.Count | Should BeGreaterThan 0
            }

            It "load balancer '$($loadBalancer.Name)' in resource group '$($loadBalancer.ResourceGroupName)' Should have at least one frontend configuration" {
                $loadBalancer.FrontendIpConfigurations.Count | Should BeGreaterThan 0
            }

            It "load balancer '$($loadBalancer.Name)' in resource group '$($loadBalancer.ResourceGroupName)' Should have at least one backend address pool" {
                $loadBalancer.BackendAddressPools.Count | Should BeGreaterThan 0
            }
        }
    }

    Context "VM Scale Set" {
        foreach ($vmScaleSet in $vmScaleSets) {
            It "vm scale set '$($vmScaleSet.Name)' in resource group '$($vmScaleSet.ResourceGroupName)' Should have at least one associated load balancer backend address pool" {
                $vmScaleSet.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations[0].IpConfigurations[0].LoadBalancerBackendAddressPools.Count | 
                Should BeGreaterThan 0
            }
        }
    }
}


