# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent)+"\Log\Log.psd1")

Function Test-SupportedMigrationScenario {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]
        $BasicLoadBalancer,

        [Parameter(Mandatory = $true)]
        [string]
        $StdLoadBalancerName
    )

    $scenario = @{
        'ExternalOrInternal' = ''
    }

    # checking source load balance SKU
    log -Message "[Test-SupportedMigrationScenario] Verifying source load balancer SKU"
    If ($BasicLoadBalancer.Sku.Name -ne 'Basic') {
        log 'Error' "[Test-SupportedMigrationScenario] The load balancer '$($BasicLoadBalancer.Name)' in resource group '$($BasicLoadBalancer.ResourceGroupName)' is SKU '$($BasicLoadBalancer.SKU.Name)'. SKU must be Basic!"
        Exit
    }
    log -Message "[Test-SupportedMigrationScenario] Source load balancer SKU is type Basic"

    # Detecting if there are any backend pools that is not virtualMachineScaleSets, if so, exit
    log -Message "[Test-SupportedMigrationScenario] Checking if there are any backend pools that is not virtualMachineScaleSets"
    foreach ($backendAddressPool in $BasicLoadBalancer.BackendAddressPools) {
        foreach ($backendIpConfiguration in $backendAddressPool.BackendIpConfigurations) {
            if ($backendIpConfiguration.Id.split("/")[7] -ne "virtualMachineScaleSets") {
                log -Message "[Test-SupportedMigrationScenario] Basic Load Balancer has backend pools that is not virtualMachineScaleSets, exiting" -Severity "Error"
                exit
            }
        }
    }
    log -Message "[Test-SupportedMigrationScenario] All backend pools are virtualMachineScaleSets!"

    # checking that source load balancer has sub-resource configurations
    log -Message "[Test-SupportedMigrationScenario] Checking that source load balancer is configured"
    If ($BasicLoadBalancer.LoadBalancingRules.count -eq 0) {
        log 'Error' "[Test-SupportedMigrationScenario] Load balancer '$($BasicLoadBalancer.Name)' has no front end configurations, so there is nothing to migrate!"
        Exit
    }
    log -Message "[Test-SupportedMigrationScenario] Load balancer has at least 1 frontend IP configuration"

    # check that standard load balancer name is avaliable
    log -Message "[Test-SupportedMigrationScenario] Checking that standard load balancer name '$StdLoadBalancerName'"
    If ((Get-AzLoadBalancer -Name $StdLoadBalancerName -ResourceGroupName $BasicLoadBalancer.ResourceGroupName -ErrorAction SilentlyContinue)) {
        log 'Error' "[Test-SupportedMigrationScenario] New standard load balancer resource '$StdLoadBalancerName' already exists; exiting!"
        exit
    }

    # detecting if source load balancer is internal or external-facing
    log -Message "[Test-SupportedMigrationScenario] Determining if LB is internal or external based on FrontEndIPConfiguration[0]'s IP configuration"
    If (![string]::IsNullOrEmpty($BasicLoadBalancer.FrontendIpConfigurations[0].PrivateIpAddress)) {
        log -Message "[Test-SupportedMigrationScenario] FrontEndIPConfiguiration[0] is assigned a private IP address '$($BasicLoadBalancer.FrontendIpConfigurations[0].PrivateIpAddress)', so this LB is Internal"
        $scenario.ExternalOrInternal = 'Internal'
    }
    ElseIf (![string]::IsNullOrEmpty($BasicLoadBalancer.FrontendIpConfigurations[0].PublicIpAddress)) {
        log -Message "[Test-SupportedMigrationScenario] FrontEndIPConfiguiration[0] is assigned a public IP address '$($BasicLoadBalancer.FrontendIpConfigurations[0].PublicIpAddress)', so this LB is External"
        $scenario.ExternalOrInternal = 'External'
    }
    ElseIf (![string]::IsNullOrEmpty($BasicLoadBalancer.FrontendIpConfigurations[0].PublicIPPrefix)) {
        log 'Error' "[Test-SupportedMigrationScenario] FrontEndIPConfiguiration[0] is assigned a public IP prefix '$($BasicLoadBalancer.FrontendIpConfigurations[0].PublicIPPrefixText)', which is not supported for migration!"
        Exit
    }

    return $scenario
}

Export-ModuleMember -Function Test-SupportedMigrationScenario