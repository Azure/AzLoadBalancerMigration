# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")

Function Test-SupportedMigrationScenario {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]
        $BasicLoadBalancer,

        [Parameter(Mandatory = $true)]
        [ValidatePattern("^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,78}[A-Za-z0-9_])?$")]
        [string]
        $StdLoadBalancerName,

        # force
        [Parameter(Mandatory = $false)]
        [switch]
        $force
    )

    $scenario = @{
        'ExternalOrInternal' = ''
        'BackendType'        = ''
    }

    # checking source load balance SKU
    log -Message "[Test-SupportedMigrationScenario] Verifying if Load Balancer $($BasicLoadBalancer.Name) is valid for migration"

    log -Message "[Test-SupportedMigrationScenario] Verifying source load balancer SKU"
    If ($BasicLoadBalancer.Sku.Name -ne 'Basic') {
        log -ErrorAction Stop -Severity 'Error' -Message "[Test-SupportedMigrationScenario] The load balancer '$($BasicLoadBalancer.Name)' in resource group '$($BasicLoadBalancer.ResourceGroupName)' is SKU '$($BasicLoadBalancer.SKU.Name)'. SKU must be Basic!"
        return
    }
    log -Message "[Test-SupportedMigrationScenario] Source load balancer SKU is type Basic"

    # Detecting if there are any backend pools that is not virtualMachineScaleSets, if so, exit
    log -Message "[Test-SupportedMigrationScenario] Checking backend pool member types and that all backend pools are not empty"
    $backendPoolHasMembers = $false
    $backendPoolMemberTypes = @()
    $basicLBVMs = @() # array of VMs used later in the vaidation script
    foreach ($backendAddressPool in $BasicLoadBalancer.BackendAddressPools) {
        foreach ($backendIpConfiguration in $backendAddressPool.BackendIpConfigurations) {
            $backendPoolHasMembers = $true
            $backendPoolMemberType = $backendIpConfiguration.Id.split("/")[7]

            # check that backend pool NIC members is attached to a VM
            If ($backendPoolMemberType -eq 'networkInterfaces') {
                $nic = Get-AzNetworkInterface -ResourceId ($backendIpConfiguration.Id -split '/ipconfigurations/')[0]

                If (!$nic.VirtualMachineText) {
                    log -ErrorAction Stop -Severity 'Error' -Message "[Test-SupportedMigrationScenario] Load balancer '$($BasicLoadBalancer.Name)' backend pool member network interface '$($nic.id)' does not have an associated Virtual Machine. Backend pool members must be either a VMSS NIC or a NIC attached to a VM!"
                    return
                }
                Else {
                    $backendPoolMemberTypes += 'virtualMachines'

                    # add VM resources to array for later validation
                    $basicLBVMs += Get-AzVM -ResourceId $nic.VirtualMachine.id
                }
            }
            Else {
                $backendPoolMemberTypes += $backendPoolMemberType
            }
        }
    }
    If (!$backendPoolHasMembers) {
        log -ErrorAction Stop -Severity 'Error' -Message "[Test-SupportedMigrationScenario] Load balancer '$($BasicLoadBalancer.Name)' has no backend pool membership, which is not supported for migration!"
        return
    }
    If (($backendPoolMemberTypes | Sort-Object | Get-Unique).count -gt 1) {
        log -ErrorAction Stop -Message "[Test-SupportedMigrationScenario] Basic Load Balancer backend pools can contain only VMs or VMSSes, contains: '$($backendPoolMemberTypes -join ',')'" -Severity 'Error'
        return
    }
    If ($backendPoolMemberTypes[0] -eq 'virtualMachines') {
        log -Message "[Test-SupportedMigrationScenario] All backend pools members are virtualMachines!"
        $scenario.BackendType = 'VM'
    }
    ElseIf ($backendPoolMemberTypes[0] -eq 'virtualMachineScaleSets') {
        log -Message "[Test-SupportedMigrationScenario] All backend pools members are virtualMachineScaleSets!"
        $scenario.BackendType = 'VMSS'
    }
    Else {
        log -ErrorAction Stop -Message "[Test-SupportedMigrationScenario] Basic Load Balancer backend pools can contain only VMs or VMSSes, contains: '$($backendPoolMemberTypes -join ',')'" -Severity 'Error'
        return
    }

    # checking that source load balancer has sub-resource configurations
    log -Message "[Test-SupportedMigrationScenario] Checking that source load balancer is configured"
    If ($BasicLoadBalancer.LoadBalancingRules.count -eq 0) {
        log -ErrorAction Stop -Severity 'Error' -Message "[Test-SupportedMigrationScenario] Load balancer '$($BasicLoadBalancer.Name)' has no front end configurations, so there is nothing to migrate!"
        return
    }
    log -Message "[Test-SupportedMigrationScenario] Load balancer has at least 1 frontend IP configuration"

    # check if the load balancer name should be re-used, if so check if it's not standard already
    log -Message "[Test-SupportedMigrationScenario] Checking that standard load balancer name '$StdLoadBalancerName'"
    $chkStdLB = (Get-AzLoadBalancer -Name $StdLoadBalancerName -ResourceGroupName $BasicLoadBalancer.ResourceGroupName -ErrorAction SilentlyContinue)
    If ($chkStdLB) {
        log -Message "[Test-SupportedMigrationScenario] Load balancer resource '$($chkStdLB.Name)' already exists. Checking if it is a Basic SKU for migration"
        If ($chkStdLB.Sku.Name -ne 'Basic') {
            log -ErrorAction Stop -Severity 'Error' -Message "[Test-SupportedMigrationScenario] Load balancer resource '$($chkStdLB.Name)' is not a Basic SKU, so it cannot be migrated!"
            return
        }
        log -Message "[Test-SupportedMigrationScenario] Load balancer resource '$($chkStdLB.Name)' is a Basic Load Balancer. The same name will be re-used."
    }

    # detecting if source load balancer is internal or external-facing
    log -Message "[Test-SupportedMigrationScenario] Determining if LB is internal or external based on FrontEndIPConfiguration[0]'s IP configuration"
    If (![string]::IsNullOrEmpty($BasicLoadBalancer.FrontendIpConfigurations[0].PrivateIpAddress)) {
        log -Message "[Test-SupportedMigrationScenario] FrontEndIPConfiguiration[0] is assigned a private IP address '$($BasicLoadBalancer.FrontendIpConfigurations[0].PrivateIpAddress)', so this LB is Internal"
        $scenario.ExternalOrInternal = 'Internal'
    }
    ElseIf (![string]::IsNullOrEmpty($BasicLoadBalancer.FrontendIpConfigurations[0].PublicIpAddress)) {
        log -Message "[Test-SupportedMigrationScenario] FrontEndIPConfiguiration[0] is assigned a public IP address '$($BasicLoadBalancer.FrontendIpConfigurations[0].PublicIpAddress.Id)', so this LB is External"

        # Detecting if there is a frontend IPV6 configuration, if so, exit
        log -Message "[Test-SupportedMigrationScenario] Determining if there is a frontend IPV6 configuration"
        foreach ($frontendIP in $BasicLoadBalancer.FrontendIpConfigurations) {
            $pip = Get-azPublicIpAddress -Name $frontendIP.PublicIpAddress.Id.split("/")[8] -ResourceGroupName $frontendIP.PublicIpAddress.Id.split("/")[4]
            if ($pip.PublicIpAddressVersion -eq "IPv6") {
                log -Message "[Test-SupportedMigrationScenario] Basic Load Balancer is using IPV6. This is not a supported scenario. PIP Name: $($pip.Name) RG: $($pip.ResourceGroupName)" -Severity "Error" -terminateOnError
                return
            }
        }
        $scenario.ExternalOrInternal = 'External'
    }
    ElseIf (![string]::IsNullOrEmpty($BasicLoadBalancer.FrontendIpConfigurations[0].PublicIPPrefix.Id)) {
        log -ErrorAction Stop -Severity 'Error' "[Test-SupportedMigrationScenario] FrontEndIPConfiguration[0] is assigned a public IP prefix '$($BasicLoadBalancer.FrontendIpConfigurations[0].PublicIPPrefixText)', which is not supported for migration!"
        return
    }

    If ($scenario.BackendType -eq 'VMSS') {
        # create array of VMSSes associated with the load balancer for following checks
        $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object { ($_ -split '/virtualMachines/')[0].ToLower() } | Select-Object -Unique
        $basicLBVMSSs = @()
        ForEach ($vmssId in $vmssIds) {
            $basicLBVMSSs += Get-AzResource -ResourceId $vmssId | Get-AzVMSS
        }

        # Detecting if there are more than one VMSS in the backend pool, if so, exit
        # Basic Load Balancers doesn't allow more than one VMSS as a backend pool becuase they would be under different availability sets.
        # This is a sanity check to make sure that the script is not run on a Basic Load Balancer that has more than one VMSS in the backend pool.
        log -Message "[Test-SupportedMigrationScenario] Checking if there are more than one VMSS in the backend pool"
        $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object { ($_ -split '/virtualMachines/')[0].ToLower() } | Select-Object -Unique
        if ($vmssIds.count -gt 1) {
            log -ErrorAction Stop -Message "[Test-SupportedMigrationScenario] Basic Load Balancer has more than one VMSS in the backend pool, exiting" -Severity 'Error'
            return
        }
        log -message "[Test-SupportedMigrationScenario] Basic Load Balancer has only one VMSS in the backend pool"

        # check if load balancer backend pool contains VMSSes which are part of another LBs backend pools
        log -Message "[Test-SupportedMigrationScenario] Checking if backend pools contain members which are members of another load balancer's backend pools..."
        ForEach ($vmss in $basicLBVMSSs) {
            $loadBalancerAssociations = @()
            ForEach ($nicConfig in $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
                ForEach ($ipConfig in $nicConfig.ipConfigurations) {
                    ForEach ($bepMembership in $ipConfig.LoadBalancerBackendAddressPools) {
                        $loadBalancerAssociations += $bepMembership.id.split('/')[0..8] -join '/'
                    }
                }
            }

            If (($beps = $loadBalancerAssociations | Sort-Object | Get-Unique).Count -gt 1) {
                $message = @"
                [Test-SupportedMigrationScenario] One (or more) backend address pool VMSS members on basic load balancer '$($BasicLoadBalancer.Name)' is also member of
                the backend address pool on another load balancer. `nVMSS: '$($vmssId)'; `nMember of load balancer backend pools on: $beps
"@
                log 'Error' $message -terminateOnError
            }
        }
    


        # check if any VMSS instances have instance protection enabled
        log -Message "[Test-SupportedMigrationScenario] Checking for instances in backend pool member VMSS '$($vmssIds.split('/')[-1])' with Instance Protection configured"
        $vmssInstances = Get-AzVmssVM -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName ($vmssIds -split '/')[-1]

        ForEach ($instance in $vmssInstances) {
            If ($instance.ProtectionPolicy.ProtectFromScaleSetActions) {
                $message = @"
                [Test-SupportedMigrationScenario] VMSS '$($vmss.Name)' contains 1 or more instances with a ProtectFromScaleSetActions Instance Protection configured. This
                module cannot upgrade the associated load balancer because a VMSS cannot be a backend member of both basic and standard SKU load balancers. Remove the Instance
                Protection policy and re-run the module.
"@
                log -Severity 'Error'
                $vmssInstances.Remove($instance)
            }
        }
        log -Message "[Test-SupportedMigrationScenario] No VMSS instances with Instance Protection found"


        # check if any VMSS have publicIPConfigurations which must be basic sku with a basic LB and cannot be migrated to a Standard LB
        log -Message "[Test-SupportedMigrationScenario] Checking for VMSS with publicIPConfigurations"
        foreach ($vmss in $basicLBVMSSs) {
            $vmssPublicIPConfigurations = $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations | Select-Object -ExpandProperty IpConfigurations | Select-Object -ExpandProperty PublicIpAddressConfiguration
            if ($vmssPublicIPConfigurations) {
                $message = @"
                [Test-SupportedMigrationScenario] VMSS '$($vmss.Name)' has Public IP Configurations assigning Public IPs to each instance (see: https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-networking#public-ipv4-per-virtual-machine). 
                Migrating this load balancer will require removing and reassigning Public IPs--CURRENT PUBLIC IPs WILL CHANGE.
"@
                log -Severity 'Warning' -Message $message

                If (!$force.IsPresent) {
                    while ($response -ne 'y' -and $response -ne 'n') {
                        $response = Read-Host -Prompt "Do you want to continue? (y/n)"
                    }
                    If ($response -eq 'n') {
                        $message = "[Test-SupportedMigrationScenario] User chose to exit the module"
                        log -Message $message -Severity 'Error' -terminateOnError
                    }
                }
                Else {
                    $message = "[Test-SupportedMigrationScenario] -Force parameter was used, so continuing with migration"
                    log -Message $message -Severity 'Warning'
                }
            }
        }

        # check if internal LB backend VMs does not have public IPs
        If ($scenario.ExternalOrInternal -eq 'Internal') {
            log -Message "[Test-SupportedMigrationScenario] Checking if internal load balancer backend VMs have public IPs..."
            ForEach ($vmss in $basicLBVMSSs) {
                $vmssVMsHavePublicIPs = $false
                :vmssNICs ForEach ($nicConfig in $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
                    ForEach ($ipConfig in $nicConfig.ipConfigurations) {
                        If ($ipConfig.PublicIPAddressConfiguration) {
                            $message = @"
                            [Test-SupportedMigrationScenario] Internal load balancer backend VMs have public IPs and will continue to use them for outbound connectivity. VMSS: '$($vmssId)'; VMSS ipconfig: '$($ipConfig.Name)'
"@ 
                            log -Message $message -Severity 'Information'
                            $vmssVMsHavePublicIPs = $true

                            break :vmssNICs
                        }
                    }
                }

                If (!$vmssVMsHavePublicIPs) {
                    $message = "[Test-SupportedMigrationScenario] Internal load balancer backend VMs do not have Public IPs and will not have outbound internet connectivity after migration to a Standard LB. VMSS: '$($vmssId)'"
                    log -Message $message -Severity 'Warning'

                    Write-Host "In order for your VMSS instances to access the internet, you'll need to take additional action post-migration. Either add Public IPs to each VMSS instance (see: https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-networking#public-ipv4-per-virtual-machine) or assign a NAT Gateway to the VMSS instances' subnet (see: https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access)." -ForegroundColor Yellow
                    If (!$force.IsPresent) {
                        while ($response -ne 'y' -and $response -ne 'n') {
                            $response = Read-Host -Prompt "Do you want to continue? (y/n)"
                        }
                        If ($response -eq 'n') {
                            $message = "[Test-SupportedMigrationScenario] User chose to exit the module"
                            log -Message $message -Severity 'Error' -terminateOnError
                        }
                    }
                    Else {
                        $message = "[Test-SupportedMigrationScenario] -Force parameter was used, so continuing with migration"
                        log -Message $message -Severity 'Warning'
                    }
                }
            }
        }
    }

    If ($scenario.BackendType -eq 'VM') {
        # check if internal LB backend VMs does not have public IPs
        If ($scenario.ExternalOrInternal -eq 'Internal') {
            log -Message "[Test-SupportedMigrationScenario] Checking if internal load balancer backend VMs have public IPs..."
            $AllVMsHavePublicIPs = $true
            ForEach ($VM in $basicLBVMs) {
                $VMHasPublicIP = $false
                :vmNICs ForEach ($nicId in $VM.NetworkProfile.NetworkInterfaces.Id) {
                    $nicConfig = Get-AzResource -Id $nicId | Get-AzNetworkInterface
                    ForEach ($ipConfig in $nicConfig.ipConfigurations) {
                        If ($ipConfig.PublicIPAddressConfiguration.IpConfiguration) {
                            $VMHasPublicIP = $true

                            break :vmNICs
                        }
                    }
                }
                If (!$VMHasPublicIP) {
                    $AllVMsHavePublicIPs = $false
                }
            }

            If (!$AllVMsHavePublicIPs) {
                $message = "[Test-SupportedMigrationScenario] Internal load balancer backend VMs do not have Public IPs and will not have outbound internet connectivity after migration to a Standard LB."
                log -Message $message -Severity 'Warning'

                Write-Host "In order for your VMs to access the internet, you'll need to take additional action post-migration. Either add Public IPs to each VM or assign a NAT Gateway to the VM subnet (see: https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access)." -ForegroundColor Yellow
                If (!$force.IsPresent) {
                    while ($response -ne 'y' -and $response -ne 'n') {
                        $response = Read-Host -Prompt "Do you want to continue? (y/n)"
                    }
                    If ($response -eq 'n') {
                        $message = "[Test-SupportedMigrationScenario] User chose to exit the module"
                        log -Message $message -Severity 'Error' -terminateOnError
                    }
                }
                Else {
                    $message = "[Test-SupportedMigrationScenario] -Force parameter was used, so continuing with migration"
                    log -Message $message -Severity 'Warning'
                }
            }
        }
    }

    log -Message "[Test-SupportedMigrationScenario] Load Balancer '$($BasicLoadBalancer.Name)' is valid for migration"
    return $scenario
}

Export-ModuleMember -Function Test-SupportedMigrationScenario