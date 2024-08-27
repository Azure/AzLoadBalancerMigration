
<#PSScriptInfo

.VERSION 5.0.3

.GUID 836ca1ab-93b7-49a3-b1d1-b257601da1dd

.AUTHOR Microsoft

.COMPANYNAME Microsoft

.COPYRIGHT Microsoft 2023

.TAGS

.LICENSEURI

.PROJECTURI https://github.com/Azure/AzLoadBalancerMigration/tree/main/LegacyScripts/AzureILBUpgrade

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES

Removing unused variable

.PRIVATEDATA

#>

<#
  
.DESCRIPTION
***DEPRECATED***
This script has been replaced with the AzureBasicLoadBalancerUpgrade module. Please use the AzureBasicLoadBalancerUpgrade module for all future upgrades of Azure Load Balancers. See: https://learn.microsoft.com/en-us/azure/load-balancer/upgrade-basic-standard-with-powershell
  
     
.PARAMETER rgName
Name of ResourceGroup of Basic Internal Load Balancer and the Standard Internal Load Balancer, like "microsoft_rg1"
.PARAMETER oldLBName
Name of Basic Internal Load Balancer you want to upgrade.
.PARAMETER newlocation
Location where you want to place new Standard Internal Load Balancer in. For example, "centralus"
.PARAMETER newLBName
Name of the newly created Standard Internal Load Balancer.
    
.EXAMPLE
./AzureILBUpgrade.ps1 -rgName "test_InternalUpgrade_rg" -oldLBName "LBForInternal" -newlocation "centralus" -newLbName "LBForUpgrade"
   
.LINK
https://aka.ms/upgradeloadbalancerdoc
https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-overview/
   
.NOTES
Note - all paramemters are required in order to successfully create a Standard Internal Load Balancer.
   
#> 
Param(
[Parameter(Mandatory = $True)][string] $rgName,
[Parameter(Mandatory = $True)][string] $oldLBName,
#Parameters for new Standard Load Balancer
[Parameter(Mandatory = $True)][string] $newlocation,
[Parameter(Mandatory = $True)][string] $newLBName
)


#getting current loadbalancer
$lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name $oldLbName
#$originalIP = $lb.FrontendIpConfigurations[0].PrivateIpAddress


#1. Backend subnet is always the same as the front end ip config - automatic association
$vnetName = ($lb.FrontendIpConfigurations.subnet.id).Split("/")[8]
$vnetRGName = ($lb.FrontendIpConfigurations.subnet.id).Split("/")[4]
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $vnetRGName
$backendSubnetName = $lb.FrontendIpConfigurations.subnet.id.Split("/")[10]
$backendSubnet = Get-AzVirtualNetworkSubnetConfig -Name $backendSubnetName -VirtualNetwork $vnet
$ipRange = ($backendSubnet.AddressPrefix).split("/")[0]

$newlbFrontendConfigs = $lb.FrontendIpConfigurations
$feProcessed = 1

[int]$startIp = [int]$ipRange.Split(".")[3] + 1
$startIPTest = $ipRange.Split(".")[0] + "." + $ipRange.Split(".")[1] + "." + $ipRange.Split(".")[2] + "." + $startIp

$availableIPS = (Test-AzPrivateIPAddressAvailability -VirtualNetwork $vnet -IPAddress $startIPTest).AvailableIPAddresses
#initial bit in array to check for available ips
$i = 0

#creating array to store original ips
$frontEndArray=@()

#2. Front Ends
foreach ($frontEndConfig in $newlbFrontendConfigs)
{
    Get-AzLoadBalancerFrontendIpConfig -Name ($frontEndConfig).Name -LoadBalancer $lb
    $newFrontEndConfigName = $frontEndConfig.Name
    $newSubnetId = $frontEndConfig.subnet.Id
    $ip = $frontEndConfig.PrivateIpAddress

    ##adding information to array
    $frontEndArray += $newFrontEndConfigName + "," + $frontEndConfig.PrivateIpAddress

    ##Creating variables with original IP information to be used with new load balancer creation
    New-Variable -Name "frontEndIpConfig$feProcessed" -Value (New-AzLoadBalancerFrontendIpConfig -Name $newFrontEndConfigName -PrivateIpAddress $ip -SubnetId $newSubnetId)
    #$newFrontEndIp = $availableIPS[$i]

    ## Increment Counters in loop
    $feProcessed++
    $i++
}

$rulesFrontEndIpConfig = (Get-Variable -Include frontEndIpConfig*)

#3. create inbound nat rule configs
$newlbNatRules = $lb.InboundNatRules
##looping through NAT Rules
$ruleprocessed = 1
foreach ($natRule in $newlbNatRules)
{
    ##need to get correct front end ip config
    $frontEndName = (($natRule.FrontendIPConfiguration).id).Split("/")[10]
    # $frontEndNameConfig = $rulesFrontEndIpConfig| Where-Object {$_.Value.Name -eq $frontEndName}
    $frontEndNameConfig = ((Get-Variable -Include frontEndIpConfig* | Where-Object {$_.Value.name -eq $frontEndName})).value
    New-Variable -Name "nat$ruleprocessed" -Value (New-AzLoadBalancerInboundNatRuleConfig -Name $natRule.name -FrontendIpConfiguration $frontEndNameConfig -Protocol $natRule.Protocol -FrontendPort $natRule.FrontendPort -BackendPort $natRule.BackendPort)
    $ruleprocessed++
}
$rulesNat = (Get-Variable -Include nat* | Where-Object {$_.Name -ne "natRule"})

##updating private ip address to new values
##adding a loop
$y = 1
for ($z = 0; $z -lt $newlbFrontendConfigs.count; $z++)
{
    $ip = $availableIPS[$availableIPS.count-$y]

    $lb | Set-AzLoadBalancerFrontendIpConfig -name $newlbFrontendConfigs[$z].Name -PrivateIpAddress $ip -subnet $newlbFrontendConfigs[$z].subnet

    $y++
}

$lb | Set-AzLoadBalancer

# ##update BASIC loadbalancer to reflect newly assigned IP values
# $lb | Set-AzLoadBalancer -FrontendIpConfiguration $newlbFrontendConfigs

#4. Create loadbalancer - this uses the original IP values from the basic Load Balancer
$newlb = New-AzLoadBalancer -ResourceGroupName $rgName -Name $newLbName -SKU Standard -Location $newlocation -FrontendIpConfiguration $rulesFrontEndIpConfig.Value  -InboundNatRule $rulesNat.Value #-outboundRule $outboundrule

#getting LB now after creation
$newlb = (Get-AzLoadBalancer  -ResourceGroupName $rgName -Name $newLbName)

#5. Probe configuration
$newProbes = Get-AzLoadBalancerProbeConfig -LoadBalancer $lb
foreach ($probe in $newProbes)
{
    $probeName = $probe.name
    $probeProtocol = $probe.protocol
    $probePort = $probe.port
    $probeInterval = $probe.intervalinseconds
    $probeRequestPath = $probe.requestPath
    $probeNumbers = $probe.numberofprobes
    $newlb | Add-AzLoadBalancerProbeConfig -Name $probeName -RequestPath $probeRequestPath -Protocol $probeProtocol -Port $probePort -IntervalInSeconds $probeInterval -ProbeCount $probeNumbers 
    $newlb | Set-AzLoadBalancer
}

#6. Backend configuration
$backendArray=@()
$newBackendPools = $lb.BackendAddressPools
$newlb = (Get-AzLoadBalancer -ResourceGroupName $rgName -Name $newLbName)
foreach ($newBackendPool in $newBackendPools)
{
    $existingBackendPoolConfig = Get-AzLoadBalancerBackendAddressPoolConfig -LoadBalancer $lb -Name ($newBackendPool).Name
    $newlb | Add-AzLoadBalancerBackendAddressPoolConfig -Name ($existingBackendPoolConfig).Name | Set-AzLoadBalancer
    $newlb = (Get-AzLoadBalancer -ResourceGroupName $rgName -Name $newLbName)
    #$newBackendPoolConfig
    $nics = (($lb.BackendAddressPools) | Where-Object {$_.Name -eq ($newBackendPool).name}).backendipconfigurations
    foreach ($nic in $nics)
    {
        $nicRG = $nic.id.Split("/")[4]
        $nicToAdd = Get-AzNetworkInterface -name ($nic.id).Split("/")[8] -ResourceGroupName $nicRG
        #write-host "Reconfiguring $nicToAdd.Name"
        $nicToAdd.IpConfigurations[0].LoadBalancerBackendAddressPools = $null
        Set-AzNetworkInterface -NetworkInterface $nicToAdd
        $backendArray += ($newBackendPool).Name +"," + ($nicToAdd).id
    }
}

#7. Re-adding NICs to backend pool
foreach ($backendItem in $backendArray)  
{
    $newlb = (Get-AzLoadBalancer  -ResourceGroupName $rgName -Name $newLbName)
    $lbBackend = Get-AzLoadBalancerBackendAddressPoolConfig -name ($backendItem.Split(",")[0]) -LoadBalancer $newlb
    #write-host "nic"
    $nicRG = $nic.id.Split("/")[4]
    $nicToAssociate = Get-AzNetworkInterface -name (($backendItem.Split(",")[1]).split("/")[8]) -resourcegroupname $nicRG
    #$nicToAssociate
    $nicToAssociate.IpConfigurations[0].LoadBalancerBackendAddressPools = $lbBackend
    Set-AzNetworkInterface -NetworkInterface $nicToAssociate
}

#8. create load balancer rule config
$newlb = (Get-AzLoadBalancer -ResourceGroupName $rgName -Name $newLbName)
$newLbRuleConfigs = Get-AzLoadBalancerRuleConfig -LoadBalancer $lb
foreach ($newLbRuleConfig in $newLbRuleConfigs)
{
    ##look at floating ip setting -enablefloatingIP and loaddistribution
    $floatingIPTest = $newLbRuleConfig.EnableFloatingIP
    $loadDistribution = $newLbRuleConfig.LoadDistribution
    $backendPool = (Get-AzLoadBalancerBackendAddressPoolConfig -LoadBalancer $newlb -Name ((($newLbRuleConfig.BackendAddressPool.id).split("/"))[10]))
    $lbFrontEndName = (($newLbRuleConfig.FrontendIPConfiguration).id).Split("/")[10]
    $lbFrontEndNameConfig = ((Get-Variable -Include frontEndIpConfig* | Where-Object {$_.Value.name -eq $lbFrontEndName})).value
    if ($floatingIPTest.equals($true))
    {
        $newlb | Add-AzLoadBalancerRuleConfig -Name ($newLbRuleConfig).Name -FrontendIPConfiguration $lbFrontEndNameConfig -BackendAddressPool $backendPool -Probe (Get-AzLoadBalancerProbeConfig -LoadBalancer $newlb -Name (($newLbRuleConfig.Probe.id).split("/")[10])) -Protocol ($newLbRuleConfig).protocol -FrontendPort ($newLbRuleConfig).FrontendPort -BackendPort ($newLbRuleConfig).BackendPort -IdleTimeoutInMinutes ($newLbRuleConfig).IdleTimeoutInMinutes -EnableFloatingIP -LoadDistribution $loadDistribution -DisableOutboundSNAT
    }
    else
    {
        $newlb | Add-AzLoadBalancerRuleConfig -Name ($newLbRuleConfig).Name -FrontendIPConfiguration $lbFrontEndNameConfig -BackendAddressPool $backendPool -Probe (Get-AzLoadBalancerProbeConfig -LoadBalancer $newlb -Name (($newLbRuleConfig.Probe.id).split("/")[10])) -Protocol ($newLbRuleConfig).protocol -FrontendPort ($newLbRuleConfig).FrontendPort -BackendPort ($newLbRuleConfig).BackendPort -IdleTimeoutInMinutes ($newLbRuleConfig).IdleTimeoutInMinutes -LoadDistribution $loadDistribution -DisableOutboundSNAT
    }
    $newlb | set-AzLoadBalancer


    foreach ($backendIpConfig in $backendPool.BackendIpConfigurations)
    {
        #$backendIpConfig
        $nicToAssociate = Get-AzNetworkInterface -name (($backendIpConfig.id).split("/")[8]) -ResourceGroupName $nicRG
        #$nicToAssociate
        $nicToAssociate.IpConfigurations[0].LoadBalancerBackendAddressPools = $lbBackend
        Set-AzNetworkInterface -NetworkInterface $nicToAssociate
    }
}