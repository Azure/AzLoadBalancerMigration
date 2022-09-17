$oldBasicLBName = 'lb-basic'
$oldBasicLBRG = 'rg-lbconversion'
$newStandardLBName = "$($basicLB.name)_standard"

$basicLB = Get-AzLoadBalancer -ResourceGroupName $oldBasicLBRG -Name $oldBasicLBName

$frontEndConfigs_basic = $basicLB | Get-AzLoadBalancerFrontendIpConfig
$backendConfigs_basic = $basicLB | Get-AzLoadBalancerBackendAddressPoolConfig
$probeConfigs_basic = $basicLB | Get-AzLoadBalancerProbeConfig
$ruleConfig_basic = $basicLB | Get-AzLoadBalancerRuleConfig
$inboundNatRules_basic = $basicLB | Get-AzLoadBalancerInboundNatRuleConfig
$inboundNatPools_basic = $basicLB | Get-AzLoadBalancerInboundNatPoolConfig

# export basic LB to template spec for backup
$exportedTemplatePath = Export-AzResourceGroup -ResourceGroupName $oldBasicLBRG -Resource $basicLB.Id -SkipAllParameterization | Select-Object -ExpandProperty Path
$basicLBTemplate = New-AzTemplateSpec -ResourceGroupName $oldBasicLBRG `
    -Name tspec-$oldBasicLBName `
    -Location $basicLB.Location `
    -TemplateFile $exportedTemplatePath 
    -Description "Backup of Basic LB '$oldBasicLBName' prior to migration to a Standard SKU LB '$newStandardLBName'" `
    -Version '1.0.0'

# create new load balancer
## update rule configs with new related resource IDs
ForEach ($ruleConfig in $ruleConfig_basic) {
    $ruleConfig.FrontendIPConfiguration.Id = $ruleConfig.FrontendIPConfiguration.Id -replace $oldBasicLBName,$newStandardLBName
    $ruleConfig.BackendAddressPool.Id = $ruleConfig.BackendAddressPool.Id -replace $oldBasicLBName,$newStandardLBName
    $ruleConfig.Probe.Id = $ruleConfig.Probe.Id -replace $oldBasicLBName,$newStandardLBName
    $ruleConfig.Id = $ruleConfig.Id -replace $oldBasicLBName,$newStandardLBName

    ForEach ($backendAddressPool in $ruleConfig.BackendAddressPools) {
        $backendAddressPool.id = $backendAddressPool.id -replace $oldBasicLBName,$newStandardLBName
    }
}

$standardLB = New-AzLoadBalancer -ResourceGroupName $basicLB.ResourceGroupName -Name $newStandardLBName -Location $basicLB.Location -Sku Standard `
    -FrontendIpConfiguration $frontEndConfigs_basic `
    -Probe $probeConfigs_basic `
    -BackendAddressPool $backendConfigs_basic `
    -LoadBalancingRule $ruleConfig_basic `
    -InboundNatRule $inboundNatRules_basic `
    -InboundNatPool $inboundNatPools_basic