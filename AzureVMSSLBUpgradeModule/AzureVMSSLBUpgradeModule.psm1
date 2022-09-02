# verify that required Az modules are available
$requiredModules = @(
    @{name = 'Az.Accounts'; requiredVersion = [Version]::new(2,9,0,0)}
    @{name = 'Az.Compute'; requiredVersion = [Version]::new(4,30,0,0)}
    @{name = 'Az.Network'; requiredVersion = [Version]::new(4,20,0,0)}
    @{name = 'Az.Resources'; requiredVersion = [Version]::new(6,1,0,0)}
)

$installMessage = "The '{0}' PowerShell module is not installed on this system. To install the required modules for this script, run 'Install-Module -Name Az.Accounts,Az.Compute,Az.Network,Az.Resources'"
$versionMessage = "The installed '{0}' PowerShell module version '{1}' is outdated; this script expects at least version '{2}'. To update the required modules for this script, run 'Update-Module -Name Az.Accounts,Az.Compute,Az.Network,Az.Resources'"

ForEach ($requiredModule in $requiredModules) {
    $module = Get-Module -Name $requiredModule.name -ListAvailable -Refresh

    If ([string]::IsNullOrEmpty($module)) {
        Write-Error ($installMessage -f $requiredModule.name)
        return
    }
    ElseIf ($module.Version -lt $requiredModule.requiredVersion) {
        Write-Error ($versionMessage -f $requiredModule.Name,$module.Version,$requiredModule.requiredVersion)
        return
    }
}

Import-Module $PSScriptRoot\modules\AzureVMSSLBUpgrade\AzureVMSSLBUpgrade.psd1

Export-ModuleMember -Function AzureVMSSLBUpgrade