Param (
    [string]$Location = 'eastus',
    [parameter(Mandatory = $false)][string[]]$ScenarioNumber,
    [switch]$includeHighCostScenarios,
    [switch]$includeManualConfigScenarios,
    [switch]$Cleanup, # removes all test environments (in parallel)
    [switch]$RunMigration, # executes the migration module against all test environments (in parallel),
    [parameter(Mandatory = $false)][string]$resourceGroupSuffix = ''
)

$ErrorActionPreference = 'Stop'

# causes resource graph queries to wait for results to be returned, since ARG lags behind ARM which breaks testing immediately after deployment
$env:LBMIG_WAIT_FOR_ARG = $true

If (!(Test-Path -Path ../scenarios)) {
    Write-Error "This script should be executed from the ./testEnvs/scripts directory"
    break
}
$allTemplates = Get-ChildItem -Path ../scenarios -File -Exclude bicepconfig.json -Recurse -Depth 0

If ($ScenarioNumber) {
    $templateNumberPattern = ($scenarioNumber | ForEach-Object { $_.ToString().PadLeft(3, '0') }) -join '|'
    $pattern = '^({0})\-' -f $templateNumberPattern
    $filteredTemplates = $allTemplates | Where-Object { $_.Name -match $pattern }
}
ElseIf ($includeHighCostScenarios.IsPresent -and $includeManualConfigScenarios.IsPresent) {
    $filteredTemplates = $allTemplates
}
ElseIf ($includeHighCostScenarios.IsPresent) {
    $filteredTemplates = $allTemplates | Where-Object { $_.Name -notmatch 'MANUALCONFIG' }
}
ElseIf ($includeManualConfigScenarios.IsPresent) {
    $filteredTemplates = $allTemplates | Where-Object { $_.Name -notmatch 'HIGHCOST' }
}
Else {
    $filteredTemplates = $allTemplates | Where-Object { $_.Name -notmatch 'HIGHCOST|MANUALCONFIG' }
}

Write-Verbose "Deploying templates: $($filteredTemplates.Name)"

# if '-Cleanup' switch is supplied, remove the resource groups and exit
if ($Cleanup -and $null -ne $filteredTemplates) {
    $jobs = @()

    $rgNamesToRemove = $filteredTemplates | ForEach-Object {  "rg-{0}{1}-{2}" -f $_.BaseName.split('-')[0],$resourceGroupSuffix,$_.BaseName.split('-',2)[1] }
    $rgNamesToRemove | Foreach-Object {
        "Removing Resource Group '$_'"
        $jobs += $(Remove-AzResourceGroup -Name $_ -Force -AsJob)
    }

    $jobs | Wait-Job | Receive-Job
    return
}

# if -RunMigration switch is supplied, the VMSS Load Balancer migration modules is run against all environments
if ($RunMigration -and $null -ne $filteredTemplates) {

    $ScriptBlock = {
        param($RGName)
        Write-Output $RGName
        $pwd
        Import-Module ../../module\AzureBasicLoadBalancerUpgrade  -Force
        $path = "C:\Users\$env:USERNAME\temp\AzLoadBalancerMigration\$RGName"
        New-Item -ItemType Directory -Path $path -ErrorAction SilentlyContinue
        Set-Location $path
        Start-AzBasicLoadBalancerUpgrade -ResourceGroupName $RGName -BasicLoadBalancerName lb-basic-01 -StandardLoadBalancerName lb-standard-01 -Pre -Force
    }

    $rgNamesToMigrate = $filteredTemplates | ForEach-Object {  "rg-{0}{1}-{2}" -f $_.BaseName.split('-')[0],$resourceGroupSuffix,$_.BaseName.split('-',2)[1] }
    $scenarios = Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -iin $rgNamesToMigrate}

    $jobPool = @()
    foreach($rg in $scenarios){

        While (($activeJobs = ($jobPool | Where-Object { $_.State -eq 'Running' }).count) -gt 10) {
            Write-Host "Currently $activeJobs jobs running, waiting for less than 10"
            Start-Sleep -Seconds 5
        }

        $jobPool += Start-Job -Name $rg.ResourceGroupName -ArgumentList $rg.ResourceGroupName -ScriptBlock $ScriptBlock -InitializationScript ([scriptblock]::Create("set-location '$pwd'"))
    }

    Write-Output ("Total Jobs Created: " + $scenarios.Count)
    Write-Output "-----------------------------"
    while((Get-Job -State Running).count -ne 0)
    {
        Write-Output ("Threads Running: " + (Get-Job -State Running).count)
        Start-Sleep -Seconds 5
    }
    Write-Output "-----------------------------"

    # $jobs = @()

    # $filteredTemplates |
    # Foreach-Object {
    #     "Upgrading LoadBalancer configuration in Resouce Group rg-$($_.BaseName)"
    #     $jobs += $(
    #         Start-Job -Name "$rgName deployment job" -InitializationScript { Import-Module ..\..\AzureBasicLoadBalancerUpgrade } `
    #             -ScriptBlock { Start-AzBasicLoadBalancerUpgrade `
    #                 -ResourceGroupName $input `
    #                 -BasicLoadBalancerName 'lb-basic-01' `
    #                 -StandardLoadBalancerName 'lb-std-01' -FollowLog } `
    #             -InputObject "rg-$($_.BaseName)"
    #     )
    # }

    # $jobs | Wait-Job | Receive-Job
    return
}

# deploy scenarioset-
$jobs = @()

foreach ($template in $filteredTemplates) {
    $rgTemplateName = "rg-{0}{1}-{2}" -f $template.BaseName.split('-')[0],$resourceGroupSuffix,$template.BaseName.split('-',2)[1]
    if($template.FullName -like "*.bicep"){
        $params = @{
            Name                    = "vmss-lb-deployment-$((get-date).tofiletime())"
            TemplateFile            = $template.FullName
            TemplateParameterObject = @{
                Location                  = $Location
                ResourceGroupName         = $rgTemplateName
            }
        }

        $job = New-AzSubscriptionDeployment -Location $location @params -AsJob
        $job.Name = "rg-$($template.BaseName)"
        $jobs += $job
    }

    elseif($template.Name -like "019*.json"){

        $params = @{
            Name                    = "vmss-lb-deployment-$((get-date).tofiletime())"
            TemplateFile            = $template.FullName
        }
        $null = New-AzResourceGroup -Name $rgTemplateName -Location $Location -Force -ErrorAction SilentlyContinue
        $jobs += New-AzResourceGroupDeployment -ResourceGroupName $rgTemplateName @params -AsJob
    }

    elseif($template.Name -like "*.json"){
        $params = @{
            Name                    = "vmss-lb-deployment-$((get-date).tofiletime())"
            TemplateFile            = $template.FullName
            TemplateParameterObject = @{
                Location                  = $Location
                ResourceGroupName         = $rgTemplateName
            }
        }
        $null = New-AzResourceGroup -Name $rgTemplateName -Location $Location -Force -ErrorAction SilentlyContinue
        $jobs += New-AzResourceGroupDeployment -ResourceGroupName $rgTemplateName @params -AsJob
    }
}

$jobs | Wait-Job | Foreach-Object {
    $job = $_
    If ($job.Error -or $job.State -eq 'Failed') {
        Write-Host -ForegroundColor Red -Object ""
    }
}

