# verify that required Az modules are available

If (!(Get-Module -Name Az.Accounts -ListAvailable)) {
    throw "The 'Az.Accounts' PowerShell module is not installed on this system. To install the required modules for this script, run 'Install-Module -Name Az.Accounts,Az.Compute,Az.Network,Az.Resources'"
}
If (!(Get-Module -Name Az.Compute -ListAvailable)) {
    throw "The 'Az.Compute' PowerShell module is not installed on this system. To install the required modules for this script, run 'Install-Module -Name Az.Accounts,Az.Compute,Az.Network,Az.Resources'"
}
If (!(Get-Module -Name Az.Network -ListAvailable)) {
    throw "The 'Az.Network' PowerShell module is not installed on this system. To install the required modules for this script, run 'Install-Module -Name Az.Accounts,Az.Compute,Az.Network,Az.Resources'"
}
If (!(Get-Module -Name Az.Resources -ListAvailable)) {
    throw "The 'Az.Resources' PowerShell module is not installed on this system. To install the required modules for this script, run 'Install-Module -Name Az.Accounts,Az.Compute,Az.Network,Az.Resources'"
}

Import-Module $PSScriptRoot\modules\AzureVMSSLBUpgrade\AzureVMSSLBUpgrade.psd1

Export-ModuleMember -Function AzureVMSSLBUpgrade