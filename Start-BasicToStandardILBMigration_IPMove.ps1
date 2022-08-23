$oldBasicLBName = 'lb-basic'
$foldBasicLBRG = 'rg-lbconversion'
$newStandardLBName = "$($basicLB.name)_standard"

$basicLB = Get-AzLoadBalancer -ResourceGroupName $foldBasicLBRG -Name $oldBasicLBName

$frontEndConfigs_Basic = $basicLB | Get-AzLoadBalancerFrontendIpConfig
$backendConfigs_Basic = $basicLB | Get-AzLoadBalancerBackendAddressPoolConfig
$probeConfigs_Basic = $basicLB | Get-AzLoadBalancerProbeConfig
$ruleConfig_Basic = $basicLB | Get-AzLoadBalancerRuleConfig

# Replace private IPs with new IPs from end of subnet address space
$subnetId = $frontEndConfigs_Basic[0].Subnet.Id
$vnet = Get-AzVirtualNetwork -ResourceGroupName $subnetId.split('/')[4] -Name $subnetId.split('/')[8]
$subnetConfig = Get-AzVirtualNetworkSubnetConfig -ResourceId $subnetId
$subnetAddress = $subnetConfig.AddressPrefix[0].split('/')[0]
$cidr = $subnetConfig.AddressPrefix[0].split('/')[1]

# thanks for the insight https://gist.github.com/davidjenni/7eb707e60316cdd97549b37ca95fbe93
$subnetAddress = [Net.IPAddress]::Parse($subnetAddress)

$shiftCnt = 32 - $cidr
$mask = -bnot ((1 -shl $shiftCnt) - 1)
$subnetAddressInt = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($subnetAddress.GetAddressBytes(), 0))
$subnetAddressStart = ($subnetAddressInt -band $mask) + 1
$subnetAddressEnd = ($subnetAddressInt -bor (-bnot $mask)) - 1
$subnetIPCount = $subnetAddressEnd - ($subnetAddressStart + 3)

# check that there are enough free IPs in the subnet to replace all current IPs
If (($frontEndConfigs_Basic.count * 2) -gt $subnetIPCount) {
    Write-Error "There are '$($frontEndConfigs_Basic.count)' FrontEnd IP Configs on this load balancer, but only '$($subnetIPCount)' IPs in the subnet. The subnet requires at least twice as many IPs as there are Front End IP configs on the basic load balancer!"
    exit
}

$availableIPsForAssignment = @()
$i = 1
While (($availableIPsForAssignment.count -lt $frontEndConfigs_Basic.count) -and ($i -lt $subnetIPCount)) {
    $nextIpBin = ($subnetAddressInt -bor (-bnot $mask)) - ($i + 1)
    $nextIp = ([BitConverter]::GetBytes([Net.IPAddress]::HostToNetworkOrder($nextIpBin)) | ForEach-Object { $_ } ) -join '.'

    If ((Test-AzPrivateIPAddressAvailability -VirtualNetwork $vnet -IPAddress $nextIp).Available) {
        $availableIPsForAssignment += $nextIp
    }
    $i++
}
If ($availableIPsForAssignment.count -ne $frontEndConfigs_Basic.count) {
    Write-Error "There are '$($frontEndConfigs_Basic.count)' FrontEnd IP Configs on this load balancer, but only '$($availableIPsForAssignment.count)' available IPs in the subnet. The subnet requires at least twice as many IPs as there are Front End IP configs on the basic load balancer!"
    exit
}

# replace existing FE IPs with new IPs from end of subnet address space
For ($i = 0; $i -lt $frontEndConfigs_Basic.count; $i ++) {
    $basicLB = $basicLB | Set-AzLoadBalancerFrontendIpConfig -Name $frontEndConfigs_Basic[$i].Name -PrivateIpAddress $availableIPsForAssignment[$i] -SubnetId $frontEndConfigs_Basic[$i].Subnet.Id
}
$null = $basicLB | Set-AzLoadBalancer

<#
    Search-AzGraph -Query @"
        where type == 'microsoft.network/networkInterfaces' 
        | mv-expand ipconfigs = properties.ipConfigurations 
        | mv-expand beps = ipconfigs.properties.loadBalancerBackendAddressPools 
        | where beps.id =- '$($backendPool.Id)' | project id
"@

#>

# get ipconfigs associated with each backend pool

# create new load balancer
## update rule configs with new related resource IDs
ForEach ($ruleConfig in $ruleConfig_Basic) {
    $ruleConfig.FrontendIPConfiguration.Id = $ruleConfig.FrontendIPConfiguration.Id -replace $oldBasicLBName,$newStandardLBName
    $ruleConfig.BackendAddressPool.Id = $ruleConfig.BackendAddressPool.Id -replace $oldBasicLBName,$newStandardLBName
    $ruleConfig.Probe.Id = $ruleConfig.Probe.Id -replace $oldBasicLBName,$newStandardLBName
    $ruleConfig.Id = $ruleConfig.Id -replace $oldBasicLBName,$newStandardLBName

    ForEach ($backendAddressPool in $ruleConfig.BackendAddressPools) {
        $backendAddressPool.id = $backendAddressPool.id -replace $oldBasicLBName,$newStandardLBName
    }
}

$standardLB = New-AzLoadBalancer -ResourceGroupName $basicLB.ResourceGroupName -Name $newStandardLBName -Location $basicLB.Location -Sku Standard `
    -FrontendIpConfiguration $frontEndConfigs_Basic `
    -Probe $probeConfigs_Basic `
    -BackendAddressPool $backendConfigs_Basic `
    -LoadBalancingRule $ruleConfig_Basic

