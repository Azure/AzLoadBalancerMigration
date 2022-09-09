# verify that required Az modules are available
$requiredModules = @(
    @{name = 'Az.Accounts'; requiredVersion = [Version]::new(2,9,0)}
    @{name = 'Az.Compute'; requiredVersion = [Version]::new(4,30,0)}
    @{name = 'Az.Network'; requiredVersion = [Version]::new(4,20,0)}
    @{name = 'Az.Resources'; requiredVersion = [Version]::new(6,1,0)}
)

$installMessage = "The '{0}' PowerShell module is not installed on this system. To install the required modules for this script, run 'Install-Module -Name Az.Accounts,Az.Compute,Az.Network,Az.Resources'"
$versionMessage = "The installed '{0}' PowerShell module version '{1}' is outdated; this script expects at least version '{2}'. To update the required modules for this script, run 'Update-Module -Name Az.Accounts,Az.Compute,Az.Network,Az.Resources'"

ForEach ($requiredModule in $requiredModules) {
    $module = Get-Module -Name $requiredModule.name -ListAvailable -Refresh

    If ($module.count -gt 1) {
        # import the module and use imported version number
        $multipleVersions = $true
        $module = Import-Module -Name $requiredModule.Name -PassThru
    }

    If ([string]::IsNullOrEmpty($module)) {
        Write-Error ($installMessage -f $requiredModule.name)
        return
    }
    ElseIf ($module.Version -ge $requiredModule.requiredVersion) {
        continue
    }
    else {
        Write-Error ($versionMessage -f $requiredModule.Name,$module.Version,$requiredModule.requiredVersion)

        If ($multipleVersions) {
            Write-Warning "More than one version of module '$($requiredModule.name)' exist on this system. Uninstall old versions and try again!"
        }

        return
    }
}

# Supress warnings about Az modules
Update-AzConfig -Scope Process -DisplayBreakingChangeWarning $false -AppliesTo Az > $null

Import-Module $PSScriptRoot\modules\Start-AzBasicLoadBalancerUpgrade\Start-AzBasicLoadBalancerUpgrade.psd1

Export-ModuleMember -Function Start-AzBasicLoadBalancerUpgrade