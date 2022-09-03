Param (
    [string]$Location = 'australiaeast',
    [string]$KeyVaultResourceGroupName = 'rg-vmsstestingconfig',
    [parameter(Mandatory = $false)][string[]]$ScenarioNumber,
    [switch]$includeHighCostScenarios,
    [switch]$includeManualConfigScenarios,
    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'

If (!(Test-Path -Path ../scenarios)) {
    Write-Error "This script should be executed from the ./testEnvs/scripts directory"
    break
}
$allTemplates = Get-ChildItem -Path ../scenarios -Filter *.bicep 

If ($ScenarioNumber) {
    $templateNumberPattern = ($scenarioNumber | ForEach-Object {$_.ToString().PadLeft(3,'0')}) -join '|'
    $pattern = '^({0})\-' -f $templateNumberPattern
    $filteredTemplates = $allTemplates | Where-Object {$_.Name -match $pattern}
}
ElseIf ($includeHighCostScenarios.IsPresent -and $includeManualConfigScenarios.IsPresent) {
    $filteredTemplates = $allTemplates
}
ElseIf ($includeHighCostScenarios.IsPresent) {
    $filteredTemplates = $allTemplates | Where-Object {$_.Name -notmatch 'MANUALCONFIG'}
}
ElseIf ($includeManualConfigScenarios.IsPresent) {
    $filteredTemplates = $allTemplates | Where-Object {$_.Name -notmatch 'HIGHCOST'}
}
Else {
    $filteredTemplates = $allTemplates | Where-Object {$_.Name -notmatch 'HIGHCOST|MANUALCONFIG'}
}

Write-Verbose "Deploying templates: $($filteredTemplates.Name)"

# if '-Cleanup' switch is supplied, remove the resource groups and exit
if ($Cleanup -and $null -ne $filteredTemplates) {
    $jobs = @()

    $filteredTemplates | 
    Foreach-Object {
        "Removing Resource Group rg-$($_.BaseName)"
        $jobs += $(Remove-AzResourceGroup -Name "rg-$($_.BaseName)" -Force -AsJob)
    }

    $jobs | Wait-Job | Receive-Job
    return
}

# deploy keyvault
$params = @{
    Name                    = 'prereq-deployment'
    TemplateFile            = './prereqs.bicep'
    TemplateParameterObject = @{
        Location          = $Location
        ResourceGroupName = $keyVaultResourceGroupName
    }
}

New-AzSubscriptionDeployment -Location $location @params

$keyVaultName = (
    Get-AzResourceGroupDeployment `
        -Name 'keyvault-deployment' `
        -ResourceGroupName $keyVaultResourceGroupName `
).Outputs.name.value

# deploy scenarioset-
$jobs = @()

foreach ($template in $filteredTemplates) {

    $params = @{
        Name                    = "vmss-lb-deployment-$((get-date).tofiletime())"
        TemplateFile            = $template.FullName
        TemplateParameterObject = @{
            Location                  = $Location
            ResourceGroupName         = "rg-$($template.BaseName)"
            KeyVaultName              = $keyVaultName
            KeyVaultResourceGroupName = $KeyVaultResourceGroupName
        }
    }

    $jobs += New-AzSubscriptionDeployment -Location $location @params -AsJob
}

$jobs | Wait-Job
