#Remove-Module AzureVMSSLBUpgradeModule -force
$ScriptBlock = {
    param($RGName)
    Write-Output $RGName
    Import-Module C:\Projects\VSProjects\VMSS-LoadBalander-MIgration\AzureVMSSLBMigrationModule\AzureVMSSLBMigrationModule.psd1 -Force
    $path = "C:\Users\vsantana\Desktop\temp\test_lb_migration\$RGName"
    if(!(Test-Path C:\Users\vsantana\Desktop\temp\test_lb_migration\$RGName)){
        New-Item -ItemType Directory -Path $path
    }
    Set-Location $path
    Start-AzBasicLoadBalancerMigration -ResourceGroupName $RGName -BasicLoadBalancerName lb-basic-01
}
Set-Location "C:\Users\vsantana\Desktop\temp\test_lb_migration"
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