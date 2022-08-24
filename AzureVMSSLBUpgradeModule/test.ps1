Write-Host $PSScriptRoot
Write-Host (Split-Path $PSScriptRoot -Parent)
$path = Split-Path $PSScriptRoot -Parent
Write-Host $path\BackupBasicLoadBalancer\BackupBasicLoadBalancer.psd1
Write-Host $path.Length

$path = Split-Path $PSScriptRoot -Parent
Write-Host ((Split-Path $PSScriptRoot -Parent)+"\BackupBasicLoadBalancer\BackupBasicLoadBalancer.psd1")
Write-Host ((Split-Path $PSScriptRoot -Parent)+"\BackupBasicLoadBalancer\BackupBasicLoadBalancer.psd1").length