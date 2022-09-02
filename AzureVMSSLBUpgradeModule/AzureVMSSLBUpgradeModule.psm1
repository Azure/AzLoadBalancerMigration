# verify that required Az modules are available

If (!(Get-Module -Name Az.Accounts -ListAvailable)) {
    Write-Error "The 'Az.Accounts' PowerShell module is not installed on this system. To install the required modules for this script, run 'Install-Module -Name Az.Accounts,Az.Compute,Az.Network,Az.Resources'"
    return
}
If (!(Get-Module -Name Az.Compute -ListAvailable)) {
    Write-Error "The 'Az.Compute' PowerShell module is not installed on this system. To install the required modules for this script, run 'Install-Module -Name Az.Accounts,Az.Compute,Az.Network,Az.Resources'"
    return
}
If (!(Get-Module -Name Az.Network -ListAvailable)) {
    Write-Error "The 'Az.Network' PowerShell module is not installed on this system. To install the required modules for this script, run 'Install-Module -Name Az.Accounts,Az.Compute,Az.Network,Az.Resources'"
    return
}
If (!(Get-Module -Name Az.Resources -ListAvailable)) {
    Write-Error "The 'Az.Resources' PowerShell module is not installed on this system. To install the required modules for this script, run 'Install-Module -Name Az.Accounts,Az.Compute,Az.Network,Az.Resources'"
    return
}

Import-Module $PSScriptRoot\modules\AzureVMSSLBUpgrade\AzureVMSSLBUpgrade.psd1

Export-ModuleMember -Function AzureVMSSLBUpgrade