cd .\modules\BacakupBasicLoadBalancer
New-ModuleManifest -Path BackupBasicLoadBalancer.psd1 -RootModule BackupBasicLoadBalancer -Author "Victor Santana" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru
cd ../../


New-ModuleManifest -Path AzureVMSSLBUpgrade.psd1 -RootModule AzureVMSSLBUpgrade -Author "Victor Santana" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru


New-ModuleManifest -Path Log.psd1 -RootModule Log -Author "Victor Santana" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru

New-ModuleManifest -Path PublicFEMigration.psd1 -RootModule PublicFEMigration -Author "Victor Santana" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru

New-ModuleManifest -Path RemoveLBFromVMSS.psd1 -RootModule RemoveLBFromVMSS -Author "Victor Santana" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru

