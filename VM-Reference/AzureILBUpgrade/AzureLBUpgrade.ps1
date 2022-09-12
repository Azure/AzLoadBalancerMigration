<#PSScriptInfo

.VERSION 2.0

.GUID 17cfb4a0-40ca-4cd6-b8fc-dbc04170ec79

.AUTHOR Microsoft Corporation

.COMPANYNAME Microsoft Corporation

.COPYRIGHT Microsoft Corporation. All rights reserved.

.TAGS Azure, Az, LoadBalancer, AzNetworking

#>

<#

.DESCRIPTION
This script will help you create a Standard SKU Public load balancer with the same configuration as your Basic SKU load balancer.
  
.PARAMETER oldRgName
Name of ResourceGroup of Basic Public Load Balancer, like "microsoft_rg1"
.PARAMETER oldLBName
Name of Basic Public Load Balancer you want to upgrade.
.PARAMETER newRgName
Name of the Resource Group where you want to place the newly created Standard Public Load Balancer.
.PARAMETER newlocation
Location where you want to place new Standard Public Load Balancer in. For example, "centralus"
.PARAMETER newLBName
Name of the newly created Standard Public Load Balancer.
 
.EXAMPLE
./AzureLBUpgrade.ps1 -oldRgName "test_publicUpgrade_rg" -oldLBName "LBForPublic" -newrgName "test_userInput_rg" -newlocation "centralus" -newLbName "LBForUpgrade"
 
.LINK
https://aka.ms/upgradeloadbalancerdoc
https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-overview/
  
.NOTES
Note - all paramemters are required in order to successfully create a Standard Public Load Balancer.
#>
#>
##User defined paramters
#Parameters for specified Basic Load Balancer
Param(
    [Parameter(Mandatory = $True)][string] $oldRgName,
    [Parameter(Mandatory = $True)][string] $oldLBName,
    #Parameters for new Standard Load Balancer
    [Parameter(Mandatory = $True)][string] $newRgName,
    [Parameter(Mandatory = $True)][string] $newlocation,
    [Parameter(Mandatory = $True)][string] $newLBName
)

#getting current loadbalancer
$lb = Get-AzLoadBalancer -ResourceGroupName $oldRgName -Name $oldLBName

##creating froentend ip based on new sku
New-AzResourceGroup -Name $newRgName -Location $newlocation

##collaspe #1 and #2 into one loop for each frontend config
$newlbFrontendConfigs = $lb.FrontendIpConfigurations
$feProcessed = 1

foreach ($frontEndConfig in $newlbFrontendConfigs) {   
    $frontEndConfig
    #1. create public IP
    $newFrontEndIpPublicIpName = $frontEndConfig.name + "-pip-" + $feProcessed
    $newFrontEndIpPublicIpName
    $newFrontEndIpPublicIp = New-AzPublicIpAddress -ResourceGroupName $newrgName -Name $newFrontEndIpPublicIpName -Location $newlocation -AllocationMethod static -SKU Standard
    $newFrontEndConfigName = $frontEndConfig.Name
    #2. create frontend config
    New-Variable -Name "frontEndIpConfig$feProcessed" -Value (New-AzLoadBalancerFrontendIpConfig -Name $newFrontEndConfigName -PublicIpAddress $newFrontEndIpPublicIp)
    $feProcessed++
}
$rulesFrontEndIpConfig = (Get-Variable -Include frontEndIpConfig*)


#3. create inbound nat rule configs
$newlbNatRules = $lb.InboundNatRules
##looping through NAT Rules
$ruleprocessed = 1
foreach ($natRule in $newlbNatRules) {
    ##need to get correct frontendipconfig
    $frontEndName = (($natRule.FrontendIPConfiguration).id).Split("/")[10]
    $frontEndNameConfig = ((Get-Variable -Include frontEndIpConfig* | Where-Object { $_.Value.name -eq $frontEndName })).value
    New-Variable -Name "nat$ruleprocessed" -Value (New-AzLoadBalancerInboundNatRuleConfig -Name $natRule.name -FrontendIpConfiguration $frontEndNameConfig -Protocol $natRule.Protocol -FrontendPort $natRule.FrontendPort -BackendPort $natRule.BackendPort)
    $ruleprocessed++
}
$rulesNat = (Get-Variable -Include nat* | Where-Object { $_.Name -ne "natRule" })

#4. create LoadBalancer and default outbound rule
$newlb = New-AzLoadBalancer -ResourceGroupName $newRgName -Name $newLBName -SKU Standard -Location $newlocation -FrontendIpConfiguration $rulesFrontEndIpConfig.Value  -InboundNatRule $rulesNat.Value #-outboundRule $outboundrule

#geting LB now after ceation
$newlb = (Get-AzLoadBalancer  -ResourceGroupName $newRgName -Name $newLBName)

#5. create probe config - need to be done LAST!!!
$newProbes = Get-AzLoadBalancerProbeConfig -LoadBalancer $lb
foreach ($probe in $newProbes) {
    $probeName = $probe.name
    $probeProtocol = $probe.protocol
    $probePort = $probe.port
    $probeInterval = $probe.intervalinseconds
    $probeRequestPath = $probe.requestPath
    $probeNumbers = $probe.numberofprobes
    $newlb | Add-AzLoadBalancerProbeConfig -Name $probeName -RequestPath $probeRequestPath -Protocol $probeProtocol -Port $probePort -IntervalInSeconds $probeInterval -ProbeCount $probeNumbers 
    $newlb | Set-AzLoadBalancer
}

#6. create backend pools
$newBackendPools = $lb.BackendAddressPools
## needs a loop to address multiple pools
foreach ($newBackendPool in $newBackendPools) {
    $newlb | Add-AzLoadBalancerBackendAddressPoolConfig -Name ($newBackendPool).Name | Set-AzLoadBalancer
    $newBackendPoolConfig = Get-AzLoadBalancerBackendAddressPoolConfig -LoadBalancer $newlb -Name ($newBackendPool).Name
}

$newlb = (Get-AzLoadBalancer  -ResourceGroupName $newRgName -Name $newLBName)
#7. create load balancer rule config
$newLbRuleConfigs = Get-AzLoadBalancerRuleConfig -LoadBalancer $lb
foreach ($newLbRuleConfig in $newLbRuleConfigs) {
    $backendPool = (Get-AzLoadBalancerBackendAddressPoolConfig -LoadBalancer $newlb -Name ((($newLbRuleConfig.BackendAddressPool.id).split("/"))[10]))
    $lbFrontEndName = (($newLbRuleConfig.FrontendIPConfiguration).id).Split("/")[10]
    $lbFrontEndNameConfig = ((Get-Variable -Include frontEndIpConfig* | Where-Object { $_.Value.name -eq $lbFrontEndName })).value
    $newlb | Add-AzLoadBalancerRuleConfig -Name ($newLbRuleConfig).Name -FrontendIPConfiguration $lbFrontEndNameConfig -BackendAddressPool $backendPool -Probe (Get-AzLoadBalancerProbeConfig -LoadBalancer $newlb -Name (($newLbRuleConfig.Probe.id).split("/")[10])) -Protocol ($newLbRuleConfig).protocol -FrontendPort ($newLbRuleConfig).FrontendPort -BackendPort ($newLbRuleConfig).BackendPort -IdleTimeoutInMinutes ($newLbRuleConfig).IdleTimeoutInMinutes -EnableFloatingIP -LoadDistribution SourceIP -DisableOutboundSNAT
    $newlb | set-AzLoadBalancer

}
$newlb = (Get-AzLoadBalancer  -ResourceGroupName $newRgName -Name $newLBName)
$outboundBackendPool = (Get-AzLoadBalancerBackendAddressPoolConfig -LoadBalancer $newlb)[0]
$outboundFrontEndPool = (Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $newlb)[0]

$outboundRule = New-AzLoadBalancerOutBoundRuleConfig -Name "Outboundrule" -FrontendIPConfiguration $outboundFrontEndPool -BackendAddressPool $outboundBackendPool -Protocol All -IdleTimeoutInMinutes 15 -AllocatedOutboundPort 10000
$newlb | Add-AzLoadBalancerOutboundRuleConfig -Name "Outboundrule" -FrontendIPConfiguration $outboundFrontEndPool -BackendAddressPool $outboundBackendPool -Protocol All -IdleTimeoutInMinutes 15 -AllocatedOutboundPort 10000
$newlb | Set-AzLoadBalancerOutboundRuleConfig -Name "Outboundrule" -FrontendIPConfiguration $outboundFrontEndPool -BackendAddressPool $outboundBackendPool -Protocol All -IdleTimeoutInMinutes 15 -AllocatedOutboundPort 10000
$newlb | set-AzLoadBalancer

