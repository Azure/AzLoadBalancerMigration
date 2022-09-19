#Remove-Module AzureVMSSLBUpgradeModule -force
$ScriptBlock = {
    param($RGName)
    Write-Output $RGName
    Import-Module Import-Module ..\..\AzureBasicLoadBalancerMigration -Force
    $path = "C:\Users\$env:USERNAME\Desktop\temp\AzureBasicLoadBalancerMigration\$RGName"
    New-Item -ItemType Directory -Path $path -ErrorAction SilentlyContinue
    Set-Location $path
    Start-AzBasicLoadBalancerMigration -ResourceGroupName $RGName -BasicLoadBalancerName lb-basic-01
}
Set-Location "C:\Users\$env:USERNAME\Desktop\temp\AzureBasicLoadBalancerMigration"
$scenarios = Get-AzResourceGroup -Name rg-0*

foreach($rg in $scenarios){
    Start-Job -Name $rg.ResourceGroupName -ArgumentList $rg.ResourceGroupName -ScriptBlock $ScriptBlock > $null
}

Write-Output ("Total Jobs Created: " + $scenarios.Count)
Write-Output "-----------------------------"
while((Get-Job -State Running).count -ne 0)
{
    Write-Output ("Threads Running: " + (Get-Job -State Running).count)
    Start-Sleep -Seconds 5
}
Write-Output "-----------------------------"