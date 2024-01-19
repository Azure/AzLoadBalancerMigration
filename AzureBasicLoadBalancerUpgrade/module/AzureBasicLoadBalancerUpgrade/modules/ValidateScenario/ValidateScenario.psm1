# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/GetVmssFromBasicLoadBalancer/GetVmssFromBasicLoadBalancer.psd1")

function _GetScenarioBackendType {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]
        $BasicLoadBalancer,

        # skip logging - used in validateMigration
        [Parameter(Mandatory = $false)]
        [switch]
        $skipLogging
    )

    If ($skipLogging) {
        function log {}
    }

    # Detecting if there are any backend pools that is not virtualMachineScaleSets or virtualMachines
    log -Message "[Test-SupportedMigrationScenario] Checking backend pool member types and that all backend pools are not empty"
    $backendMemberTypes = @()

    # get backend types from backend pools
    foreach ($backendAddressPool in $BasicLoadBalancer.BackendAddressPools) {
        foreach ($backendIpConfiguration in $backendAddressPool.BackendIpConfigurations) {
            $backendMemberType = $backendIpConfiguration.Id.split("/")[7]
    
            # check that backend pool NIC members is attached to a VM
            If ($backendMemberType -eq 'networkInterfaces') {
                $backendMemberTypes += 'virtualMachines'
            }
        
            Else {
                $backendMemberTypes += $backendMemberType
            }
        }
    }

    # get backend types from NAT rules
    foreach ($inboundNatRule in $BasicLoadBalancer.InboundNatRules) {
        foreach ($backendIpConfiguration in $inboundNatRule.BackendIpConfiguration) {
            $backendMemberType = $backendIpConfiguration.Id.split("/")[7]
    
            # check that nat rule NIC members is attached to a VM
            If ($backendMemberType -eq 'networkInterfaces') {
                $backendMemberTypes += 'virtualMachines'
            }
        
            Else {
                $backendMemberTypes += $backendMemberType
            }
        }
    }


    If (($backendMemberTypes | Sort-Object | Get-Unique).count -gt 1) {
        log -ErrorAction Stop -Message "[Test-SupportedMigrationScenario] Basic Load Balancer backend pools can contain only VMs or VMSSes, contains: '$($backendMemberTypes -join ',')'" -Severity 'Error'
        return
    }
    If ($backendMemberTypes[0] -eq 'virtualMachines') {
        log -Message "[Test-SupportedMigrationScenario] All backend pools members are virtualMachines!"
        $backendType = 'VM'
    }
    ElseIf ($backendMemberTypes[0] -eq 'virtualMachineScaleSets') {
        log -Message "[Test-SupportedMigrationScenario] All backend pools members are virtualMachineScaleSets!"
        $backendType = 'VMSS'
    }
    ElseIf ([string]::IsNullOrEmpty($backendMemberTypes[0])) {
        log -Message "[Test-SupportedMigrationScenario] Basic Load Balancer backend pools are empty"
        $backendType = 'Empty'
    }
    Else {
        log -ErrorAction Stop -Message "[Test-SupportedMigrationScenario] Basic Load Balancer backend pools can contain only VMs or VMSSes, contains: '$($backendMemberTypes -join ',')'" -Severity 'Error'
        return
    }

    return $backendType
}

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

        
        [Parameter(Mandatory = $false)]
        [string[]]
        $basicLBBackendIds,

        # force
        [Parameter(Mandatory = $false)]
        [switch]
        $force,

        # pre-release feature switch
        [Parameter(Mandatory = $false)]
        [switch]
        $Pre
    )

    $scenario = New-Object -TypeName psobject -Property @{
        'ExternalOrInternal'              = ''
        'BackendType'                     = ''
        'VMsHavePublicIPs'                = $false
        'VMSSInstancesHavePublicIPs'      = $false
        'SkipOutboundRuleCreationMultiBE' = $false
    }

    $progressParams = @{
        Activity = "Validating Migration Scenario"
        ParentId = 2
    }

    # checking source load balance SKU
    Write-Progress -Status "[Test-SupportedMigrationScenario] Verifying if Load Balancer $($BasicLoadBalancer.Name) is valid for migration" -PercentComplete 0 @progressParams
    log -Message "[Test-SupportedMigrationScenario] Verifying if Load Balancer $($BasicLoadBalancer.Name) is valid for migration"

    log -Message "[Test-SupportedMigrationScenario] Verifying source load balancer SKU"
    If ($BasicLoadBalancer.Sku.Name -ne 'Basic') {
        log -ErrorAction Stop -Severity 'Error' -Message "[Test-SupportedMigrationScenario] The load balancer '$($BasicLoadBalancer.Name)' in resource group '$($BasicLoadBalancer.ResourceGroupName)' is SKU '$($BasicLoadBalancer.SKU.Name)'. SKU must be Basic!"
        return
    }
    log -Message "[Test-SupportedMigrationScenario] Source load balancer SKU is type Basic"

    # Detecting if there are any backend pools that is not virtualMachineScaleSets or virtualMachines
    $backendType = _GetScenarioBackendType -BasicLoadBalancer $BasicLoadBalancer
    $scenario.BackendType = $backendType

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
        log -Message "[Test-SupportedMigrationScenario] Load balancer does not have a frontend IPV6 configuration"

        $scenario.ExternalOrInternal = 'External'
    }
    ElseIf (![string]::IsNullOrEmpty($BasicLoadBalancer.FrontendIpConfigurations[0].PublicIPPrefix.Id)) {
        log -ErrorAction Stop -Severity 'Error' "[Test-SupportedMigrationScenario] FrontEndIPConfiguration[0] is assigned a public IP prefix '$($BasicLoadBalancer.FrontendIpConfigurations[0].PublicIPPrefixText)', which is not supported for migration!"
        return
    }

    If ($scenario.BackendType -eq 'VMSS') {
        Write-Progress -Status "Validating VMSS backend scenario parameters" -PercentComplete 50 @progressParams

        # create array of VMSSes associated with the load balancer for following checks
        $basicLBVMSSs = GetVmssFromBasicLoadBalancer -BasicLoadBalancer $BasicLoadBalancer

        # Detecting if there are more than one VMSS in the backend pool, if so, exit
        # Basic Load Balancers doesn't allow more than one VMSS as a backend pool becuase they would be under different availability sets.
        # This is a sanity check to make sure that the script is not run on a Basic Load Balancer that has more than one VMSS in the backend pool.
        log -Message "[Test-SupportedMigrationScenario] Checking if there are more than one VMSS in the backend pool"
        $vmssIds = $basicLBVMSSs.id
        if ($vmssIds.count -gt 1) {
            log -ErrorAction Stop -Message "[Test-SupportedMigrationScenario] Basic Load Balancer has more than one VMSS in the backend pool, exiting" -Severity 'Error'
            return
        }
        log -message "[Test-SupportedMigrationScenario] Basic Load Balancer has only one VMSS in the backend pool"

        # check if load balancer backend pool contains VMSSes which are part of another LBs backend pools
        log -Message "[Test-SupportedMigrationScenario] Checking if backend pools contain members which are members of another load balancer's backend pools..."
        ForEach ($vmss in $basicLBVMSSs) {

            try {
                $nicBackendPoolMembershipsIds = @()
                $nicBackendPoolMembershipsIds += $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations.ipCOnfigurations.LoadBalancerBackendAddressPools.id | Sort-Object | Get-Unique
                $differentMembership = Compare-Object $nicBackendPoolMembershipsIds $basicLBBackendIds
            }
            catch {
                $message = "[Test-SupportedMigrationScenario] Error comparing NIC backend pool memberships ($($nicBackendPoolMembershipsIds -join ',')) to basicLBBackendIds ($($basicLBBackendIds -join ',')). Error: $($_.Exception.Message)"
                log -Message $message -Severity 'Error' -terminateOnError
            }

            If ($differentMembership) {
                ForEach ($membership in $differentMembership) {
                    switch ($membership.sideIndicator) {
                        '<=' {
                            log -Message "[Test-SupportedMigrationScenario] VMSS '$($vmss.Id)' has a NIC IP configuration associated with backend pool ID '$($membership.Inputobject)', which does not belong to the Basic Load Balancer(s) to be migrated. To migrate this scenario, use the -MultiLBConfig parameter to specify multiple Basic Load Balancers to migrate at the same time." -Severity Error -terminateOnError
                        }
                    }
                }
            }
            Else {
                log -Message "[Test-SupportedMigrationScenario] All VMSS load balancer associations are with the Basic LB(s) to be migrated." -Severity Information
            }
        }
    
        # check if any VMSS instances have instance protection enabled
        log -Message "[Test-SupportedMigrationScenario] Checking for instances in backend pool member VMSS '$($vmssIds.split('/')[-1])' with Instance Protection configured"
        $vmssInstances = Get-AzVmssVM -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName ($vmssIds -split '/')[-1]

        ForEach ($instance in $vmssInstances) {
            If ($instance.ProtectionPolicy.ProtectFromScaleSetActions) {
                $message = "[Test-SupportedMigrationScenario] VMSS '$($vmss.Name)' contains 1 or more instances with a ProtectFromScaleSetActions Instance Protection configured. This module cannot upgrade the associated load balancer because a VMSS cannot be a backend member of both basic and standard SKU load balancers. Remove the Instance Protection policy and re-run the module."
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

                $scenario.VMSSInstancesHavePublicIPs = $true

                If (!$force.IsPresent) {
                    $response = $null
                    while ($response -ne 'y' -and $response -ne 'n') {
                        $response = Read-Host -Prompt "Do you want to continue? (y/n)"
                    }
                    If ($response -eq 'n') {
                        $message = "[Test-SupportedMigrationScenario] User chose to exit the module"
                        log -Message $message -Severity 'Error' -terminateOnError
                    }
                }
                Else {
                    $message = "[Test-SupportedMigrationScenario] -Force or -ValidateOnly parameter was used, so continuing with migration validation"
                    log -Message $message -Severity 'Warning'
                }
            }
        }

        # check if internal LB backend VMs does not have public IPs
        log -Message "[Test-SupportedMigrationScenario] Checking if internal load balancer backend VMSS VMs have public IPs..."
        ForEach ($vmss in $basicLBVMSSs) {
            $vmssVMsHavePublicIPs = $false
            :vmssNICs ForEach ($nicConfig in $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
                ForEach ($ipConfig in $nicConfig.ipConfigurations) {
                    If ($ipConfig.PublicIPAddressConfiguration) {
                        $message = @"
                        [Test-SupportedMigrationScenario] Internal load balancer backend VMs have public IPs and will continue to use them for outbound connectivity. VMSS: '$($vmssId)'; VMSS ipconfig: '$($ipConfig.Name)'
"@ 
                        log -Message $message
                        $vmssVMsHavePublicIPs = $true

                        break :vmssNICs
                    }
                }
            }

            If ($vmssVMsHavePublicIPs) {
                $message = "[Test-SupportedMigrationScenario] Backend VMSS instances have instance-level Public IP addresses which must be upgraded to Standard SKU along with the Load Balancer."
                log -Message $message -Severity 'Warning'
    
                Write-Host "In order to access your VMSS instances from the Internet over a Standard SKU instance-level Public IP address, the associated NIC or NIC's subnet must have an attached Network Security Group (NSG) which explicitly allows desired traffic, which is not a requirement for Basic SKU Public IPs. See 'Security' at https://learn.microsoft.com/azure/virtual-network/ip-services/public-ip-addresses#sku" -ForegroundColor Yellow
                If (!$force.IsPresent) {
                    $response = $null
                    while ($response -ne 'y' -and $response -ne 'n') {
                        $response = Read-Host -Prompt "Do you want to continue? (y/n)"
                    }
                    If ($response -eq 'n') {
                        $message = "[Test-SupportedMigrationScenario] User chose to exit the module"
                        log -Message $message -Severity 'Error' -terminateOnError
                    }
                }
                Else {
                    $message = "[Test-SupportedMigrationScenario] -Force or -ValidateOnly parameter was used, so continuing with migration validation"
                    log -Message $message -Severity 'Warning'
                }
            }

            If (!$vmssVMsHavePublicIPs -and $scenario.ExternalOrInternal -eq 'Internal') {
                $message = "[Test-SupportedMigrationScenario] Internal load balancer backend VMs do not have Public IPs and will not have outbound internet connectivity after migration to a Standard LB. VMSS: '$($vmss.Name)'"
                log -Message $message -Severity 'Warning'

                Write-Host "In order for your VMSS instances to access the internet, you'll need to take additional action post-migration. Either add Public IPs to each VMSS instance (see: https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-networking#public-ipv4-per-virtual-machine) or assign a NAT Gateway to the VMSS instances' subnet (see: https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access)." -ForegroundColor Yellow
                If (!$force.IsPresent) {
                    $response = $null
                    while ($response -ne 'y' -and $response -ne 'n') {
                        $response = Read-Host -Prompt "Do you want to continue? (y/n)"
                    }
                    If ($response -eq 'n') {
                        $message = "[Test-SupportedMigrationScenario] User chose to exit the module"
                        log -Message $message -Severity 'Error' -terminateOnError
                    }
                }
                Else {
                    $message = "[Test-SupportedMigrationScenario] -Force or -ValidateOnly parameter was used, so continuing with migration validation"
                    log -Message $message -Severity 'Warning'
                }
            }

            # check is vmss is a managed service fabric cluster, which are not supported for upgrade
            log -Message "[Test-SupportedMigrationScenario] Checking whether VMSS scale set '$($vmss.name)' is a managed Service Fabric cluster..."
            If ($vmss.VirtualMachineProfile.ExtensionProfile.Extensions.type -contains 'ServiceFabricMCNode') {

                $message = "[Test-SupportedMigrationScenario] VMSS appears to be a Managed Service Fabric cluster based on extension profile (includes type 'ServiceFabricMCNode'). Managed Service Fabric clusters are not supported for upgrade."
                log -Message $message -Severity 'Error' -terminateOnError
            }
         
            # check if vmss is service fabric cluster, warn about possible downtime
            log -Message "[Test-SupportedMigrationScenario] Checking whether VMSS scale set '$($vmss.name)' is a Service Fabric cluster..."
            If ($vmss.VirtualMachineProfile.ExtensionProfile.Extensions.type -contains 'ServiceFabricNode' -or 
                $vmss.VirtualMachineProfile.ExtensionProfile.Extensions.type -contains 'ServiceFabricLinuxNode') {

                $message = "[Test-SupportedMigrationScenario] VMSS appears to be a Service Fabric cluster based on extension profile. SF Clusters experienced potentially significant downtime during migration using this PowerShell module. In testing, a 5-node Bronze cluster was unavailable for about 30 minutes and a 5-node Silver cluster was unavailable for about 45 minutes. Shutting down the cluster VMSS prior to initiating migration will result in a more consistent experience of about 5 minutes to complete the LB migration. For Service Fabric clusters that require minimal / no connectivity downtime, adding a new node type with standard load balancer and IP resources is a better solution."
                log -Message $message -Severity 'Warning'

                Write-Host "Do you want to proceed with the migration of your Service Fabric Cluster's Load Balancer?" -ForegroundColor Yellow
                If (!$force.IsPresent) {
                    $response = $null
                    while ($response -ne 'y' -and $response -ne 'n') {
                        $response = Read-Host -Prompt "Do you want to continue? (y/n)"
                    }
                    If ($response -eq 'n') {
                        $message = "[Test-SupportedMigrationScenario] User chose to exit the module"
                        log -Message $message -Severity 'Error' -terminateOnError
                    }

                    If ($env:POWERSHELL_DISTRIBUTION_CHANNEL -eq 'CloudShell') {
                        log -Severity Error -Message "Due to possiblity of timeouts, the -Force parameter must be specified when attempting to migrate a Service Fabric cluster LB in Azure Cloud Shell. Use at your own risk!" -terminateOnError
                    }
                }
                Else {
                    $message = "[Test-SupportedMigrationScenario] -Force or -ValidateOnly parameter was used, so continuing with migration validation"
                    log -Message $message -Severity 'Warning'
                }
            }
        }
    }

    If ($scenario.BackendType -eq 'VM') {
        Write-Progress -Status "Validating VM backend scenario parameters" -PercentComplete 50 @progressParams

        # create array of VMs associated with the load balancer for following checks and verify that NICs are associated to VMs
        $basicLBVMs = @()
        $basicLBVMNics = @()
        foreach ($backendAddressPool in $BasicLoadBalancer.BackendAddressPools) {
            foreach ($backendIpConfiguration in $backendAddressPool.BackendIpConfigurations) {        
                $nic = Get-AzNetworkInterface -ResourceId ($backendIpConfiguration.Id -split '/ipconfigurations/')[0]
        
                If (!$nic.VirtualMachineText) {
                    log -ErrorAction Stop -Severity 'Error' -Message "[Test-SupportedMigrationScenario] Load balancer '$($BasicLoadBalancer.Name)' backend pool member network interface '$($nic.id)' does not have an associated Virtual Machine. Backend pool members must be either a VMSS NIC or a NIC attached to a VM!"
                    return
                }
                Else {      
                    # add VM resources to array for later validation
                    $basicLBVMs += Get-AzVM -ResourceId $nic.VirtualMachine.id

                    # add VM nics to array for later validation
                    $basicLBVMNics += $nic
                }
            }
        }

        # check if load balancer backend pool contains VMs which are part of another LBs backend pools
        log -Message "[Test-SupportedMigrationScenario] Checking if backend pools contain members which are members of another load balancer's backend pools..."

        ## compare nic backend pool memberships to basicLBBackendIds
        try {
            $nicBackendPoolMembershipsIds = @()
            $nicBackendPoolMembershipsIds += $basicLBVMNics.IpConfigurations.loadBalancerBackendAddressPools.id | Sort-Object | Get-Unique
            $differentMembership = Compare-Object $nicBackendPoolMembershipsIds $basicLBBackendIds
        }
        catch {
            $message = "[Test-SupportedMigrationScenario] Error comparing NIC backend pool memberships ($($nicBackendPoolMembershipsIds -join ',')) to basicLBBackendIds ($($basicLBBackendIds -join ',')). Error: $($_.Exception.Message)"
            log -Message $message -Severity 'Error' -terminateOnError
        }

        If ($differentMembership) {
            ForEach ($membership in $differentMembership) {
                switch ($membership.sideIndicator) {
                    '<=' {
                        log -Message "[Test-SupportedMigrationScenario] A VM NIC IP configuration in the backend pool of the basic load balancer(s) to be migrated is associated with backend pool ID '$($membership.InputObject)', which does not belong to the Basic Load Balancer(s) to be migrated. To migrate this scenario, use the -MultiLBConfig parameter to specify multiple Basic Load Balancers to migrate at the same time." -Severity Error -terminateOnError
                    }
                }
            }
        }
        Else {
            log -Message "[Test-SupportedMigrationScenario] All VM load balancer associations are with the Basic LB(s) to be migrated." -Severity Information
        }        

        # check if internal LB backend VMs does not have public IPs
        log -Message "[Test-SupportedMigrationScenario] Checking if backend VMs have public IPs..."
        $AnyVMsHavePublicIP = $false
        $AllVMsHavePublicIPs = $true
        ForEach ($VM in $basicLBVMs) {
            $VMHasPublicIP = $false
            :vmNICs ForEach ($nicId in $VM.NetworkProfile.NetworkInterfaces.Id) {
                $nicConfig = Get-AzResource -Id $nicId | Get-AzNetworkInterface
                ForEach ($ipConfig in $nicConfig.ipConfigurations) {
                    If ($ipConfig.PublicIPAddress.Id) {
                        $AnyVMsHavePublicIP = $true
                        $VMHasPublicIP = $true

                        break :vmNICs
                    }
                }
            }
            If (!$VMHasPublicIP) {
                $AllVMsHavePublicIPs = $false
            }
        }

        # check if some backend VMs have ILIPs but not others
        If ($AnyVMsHavePublicIP -and !$AllVMsHavePublicIPs -and $Scenario.ExternalOrInternal -eq 'External') {
            $message = "[Test-SupportedMigrationScenario] Some but not all load balanced VMs have instance-level Public IP addresses and the load balancer is external. It is not supported to create an Outbound rule on a LB when any backend VM has a PIP; therefore, VMs which do not have PIPs will loose outbound internet connecticity post-migration."
            log -Message $message -Severity 'Warning'

            Write-Host "In order for all for VMs to access the internet post-migration, add PIPs to all VMs, a NAT Gateway to the subnet, or other outbound option (see: https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access)" -ForegroundColor Yellow
            If (!$force.IsPresent) {
                $response = $null
                while ($response -ne 'y' -and $response -ne 'n') {
                    $response = Read-Host -Prompt "Do you want to continue? (y/n)"
                }
                If ($response -eq 'n') {
                    $message = "[Test-SupportedMigrationScenario] User chose to exit the module"
                    log -Message $message -Severity 'Error' -terminateOnError
                }
            }
            Else {
                $message = "[Test-SupportedMigrationScenario] -Force or -ValidateOnly parameter was used, so continuing with migration validation"
                log -Message $message -Severity 'Warning'
            }
        }

        # warn about requirement to allow traffic on standard sku ilips
        If ($AnyVMsHavePublicIP) {
            $scenario.VMsHavePublicIPs = $true

            $message = "[Test-SupportedMigrationScenario] Load Balance VMs have instance-level Public IP addresses, all of which must be upgraded to Standard SKU along with the Load Balancer."
            log -Message $message -Severity 'Warning'

            Write-Host "In order to access your VMs from the Internet over a Standard SKU instance-level Public IP address, the associated NIC or NIC's subnet must have an attached Network Security Group (NSG) which explicity allows desired traffic, which is not a requirement for Basic SKU Public IPs. See 'Security' at https://learn.microsoft.com/azure/virtual-network/ip-services/public-ip-addresses#sku" -ForegroundColor Yellow
            If (!$force.IsPresent) {
                $response = $null
                while ($response -ne 'y' -and $response -ne 'n') {
                    $response = Read-Host -Prompt "Do you want to continue? (y/n)"
                }
                If ($response -eq 'n') {
                    $message = "[Test-SupportedMigrationScenario] User chose to exit the module"
                    log -Message $message -Severity 'Error' -terminateOnError
                }
            }
            Else {
                $message = "[Test-SupportedMigrationScenario] -Force or -ValidateOnly parameter was used, so continuing with migration validation"
                log -Message $message -Severity 'Warning'
            }
        }

        # warn that internal LB backends will have no outbound connectivity
        If (!$AllVMsHavePublicIPs -and $scenario.ExternalOrInternal -eq 'Internal') {
            $message = "[Test-SupportedMigrationScenario] Internal load balancer backend VMs do not have Public IPs and will not have outbound internet connectivity after migration to a Standard LB."
            log -Message $message -Severity 'Warning'

            Write-Host "In order for your VMs to access the internet, you'll need to take additional action before or after migration. Either add Public IPs to each VM, assign a NAT Gateway to the VM subnet, or route internet traffic through an NVA (see: https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access)." -ForegroundColor Yellow
            If (!$force.IsPresent) {
                $response = $null
                while ($response -ne 'y' -and $response -ne 'n') {
                    $response = Read-Host -Prompt "Do you want to continue? (y/n)"
                }
                If ($response -eq 'n') {
                    $message = "[Test-SupportedMigrationScenario] User chose to exit the module"
                    log -Message $message -Severity 'Error' -terminateOnError
                }
            }
            Else {
                $message = "[Test-SupportedMigrationScenario] -Force or -ValidateMigration parameter was used, so continuing with migration validation"
                log -Message $message -Severity 'Warning'
            }
        }
    }


    # if the basic lb is external and has multiple backend pools, warn that the migration will not create a default outbound rule
    If ($scenario.ExternalOrInternal -eq 'External' -and $BasicLoadBalancer.BackendAddressPools.Count -gt 1 -and 
        (!$scenario.VMsHavePublicIPs -and !$scenario.VMSSInstancesHavePublicIPs)) {

        $scenario.SkipOutboundRuleCreationMultiBE = $true

        $message = "[Test-SupportedMigrationScenario] Basic Load Balancer '$($BasicLoadBalancer.Name)' has multiple backend pools and is external. The migration will not create a default outbound rule on the Standard Load Balancer. You will need to create a default outbound rule manually post-migration; until you do, your backend pool members will have no outbound internet access."
        log -Message $message -Severity 'Warning'

        Write-Host "Basic Load Balancer '$($BasicLoadBalancer.Name)' has multiple backend pools and is external. The migration will not create a default outbound rule on the Standard Load Balancer. You will need to create a default outbound rule manually post-migration." -ForegroundColor Yellow
        If (!$force.IsPresent) {
            $response = $null
            while ($response -ne 'y' -and $response -ne 'n') {
                $response = Read-Host -Prompt "Do you want to continue? (y/n)"
            }
            If ($response -eq 'n') {
                $message = "[Test-SupportedMigrationScenario] User chose to exit the module"
                log -Message $message -Severity 'Error' -terminateOnError
            }
        }
        Else {
            $message = "[Test-SupportedMigrationScenario] -Force or -ValidateOnly parameter was used, so continuing with migration validation"
            log -Message $message -Severity 'Warning'
        }
    }

    Write-Progress -Status "Finished scenario validation" -PercentComplete 100 @progressParams

    log -Message "[Test-SupportedMigrationScenario] Detected migration scenario: $($scenario | ConvertTo-Json -Depth 10 -Compress)"
    log -Message "[Test-SupportedMigrationScenario] Load Balancer '$($BasicLoadBalancer.Name)' is valid for migration"
    return $scenario
}

Function Test-SupportedMultiLBScenario {
    param (
        [Parameter(Mandatory = $true)]
        [psobject[]]
        $multiLBConfig
    )

    log -Message "[Test-SupportedMultiLBScenario] Verifying if Multi-LB configuration is valid for migration"

    # check that backend type is not 'empty', meaning there is no reason to use -multiLBConfig
    log -Message "[Test-SupportedMultiLBScenario] Checking that backend type is not 'empty' for any of the multi load balancers"
    If ($multiLBConfig.scenario.backendType -contains 'Empty') {
        log -ErrorAction Stop -Severity 'Error' -Message "[Test-SupportedMultiLBScenario] One or more Basic Load Balancers backend is empty, for which Load Balancers, there no reason to use -multiLBConfig. Use standalone migrations or remove the load balancer with the empty backend from the -multiLBConfig parameter"
        return
    }

    # check that all backend pool members are VMs or VMSSes
    log -Message "[Test-SupportedMultiLBScenario] Checking that all backend pool members are VMs or VMSSes"
    $backendMemberTypes = ($multiLBConfig.scenario.BackendType | Sort-Object | Get-Unique)

    If ($backendMemberTypes.count -gt 1) {
        log -ErrorAction Stop -Severity 'Error' -Message "[Test-SupportedMultiLBScenario] Basic Load Balancer backend pools can contain only VMs or VMSSes, contains: '$($backendMemberTypes -join ',')'"
        return
    }
    Else {
        log -Message "[Test-SupportedMultiLBScenario] All backend pool members are '$($backendMemberTypes)'"
    }

    # check that standard load balancer names are different if basic load balancers are in the same resource group
    log -Message "[Test-SupportedMultiLBScenario] Checking that standard load balancer names are different if basic load balancers are in the same resource group"

    # check standard load balancer names will be unique in the same resource group
    ForEach ($config in $multiLBConfig) {
        $matchingConfigs = @()

        If ([string]::IsNullOrEmpty) {
            $StdLoadBalancerName = $config.BasicLoadBalancer.Name
        }
        Else {
            $StdLoadBalancerName = $config.StandardLoadBalancerName
        }

        $matchingConfigs += $multiLBConfig | Where-Object { 
            (([string]::IsNullOrEmpty($_.StandardLoadBalancerName) -and $_.BasicLoadBalancer.Name -eq $StdLoadBalancerName) -or
            ($_.StandardLoadBalancerName -eq $StdLoadBalancerName)) -and
            ($_.BasicLoadBalancer.ResourceGroupName -eq $config.BasicLoadBalancer.ResourceGroupName) }

        If ($matchingConfigs.count -gt 1) {
            log -Severity Error -Message "[Test-SupportedMultiLBScenario] Standard Load Balancer name '$($StdLoadBalancerName)' will be used more than once in resource group '$($config.BasicLoadBalancer.ResourceGroupName)'. Standard Load Balancer names must be unique in the same resource group. If renaming load balancers with the -standardLoadBalancerName parameter, make sure new names are unique." -terminateOnError
        }
    }

    # check that that the provided load balancer do share backend pool members - using -multiLBConfig when backend is not shared adds risk
    log -Message "[Test-SupportedMultiLBScenario] Checking that that the provided load balancer do share backend pool members - using -multiLBConfig when backend is not shared adds risk"

    ## shared backend should be a single VMSS
    If ($multiLBConfig[0].scenario.backendType -eq 'VMSS') {
        $basicLBBackends = @()
        ForEach ($config in $multiLBConfig) {
            $basicLBBackends += $config.BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | ForEach-Object {$_.split('/virtualMachines/')[0]}
        }
        $groupedBackends = $basicLBBackends | Sort-Object | Get-Unique

        If ($groupedBackends.Count -gt 1) {
            log -Severity Error -Message "[Test-SupportedMultiLBScenario] The provided Basic Load Balancers do not share backend pool members (more than one backend VMSS found: '$($groupedBackends)'). Using -multiLBConfig when backend is not shared adds risk and complexity in recovery." -terminateOnError
        }
        Else {
            log -Message "[Test-SupportedMultiLBScenario] The provided Basic Load Balancers share '$($groupedBackends.count)' backend pool members."
        }
    }

    ## shared backend should be a single Availability Set for VMs
    If ($multiLBConfig[0].scenario.backendType -eq 'VM') {
        $nicIDs = @() 
        ForEach ($basicLoadBalancer in $multiLBConfig.BasicLoadBalancer) {
            foreach ($backendAddressPool in $BasicLoadBalancer.BackendAddressPools) {
                foreach ($backendIpConfiguration in ($backendAddressPool.BackendIpConfigurations | Select-Object -Property Id -Unique)) {
                    $nicIDs += "'$(($backendIpConfiguration.Id -split '/ipconfigurations/')[0])'"
                }
            }
            foreach ($inboundNatRule in $BasicLoadBalancer.inboundNatRules) {
                foreach ($backendIpConfiguration in ($inboundNatRule.BackendIpConfiguration | Select-Object -Property Id -Unique)) {
                    $nicIDs += "'$(($backendIpConfiguration.Id -split '/ipconfigurations/')[0])'"
                }
            }
        }

        $joinedNicIDs = $nicIDs -join ','

        $graphQuery = @"
        Resources |
            where type =~ 'microsoft.network/networkinterfaces' and id in~ ($joinedNicIDs) | 
            project lbNicVMId = tolower(tostring(properties.virtualMachine.id)) |
            join ( Resources | where type =~ 'microsoft.compute/virtualmachines' | project vmId = tolower(id), availabilitySetId = coalesce(properties.availabilitySet.id, 'NO_AVAILABILITY_SET') on `$left.lbNicVMId == `$right.vmId |
            project availabilitySetId
"@

        log -Severity Verbose -Message "Graph Query Text: `n$graphQuery"

        $waitingForARG = $false
        $timeoutStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        do {        
            If (!$waitingForARG) {
                log -Message "[UpgradeVMPublicIP] Querying Resource Graph for PIPs associated with VMs in the backend pool(s)..."
            }
            Else {
                log -Message "[UpgradeVMPublicIP] Waiting 15 seconds before querying ARG again (total wait time up to 15 minutes before failure)..."
                Start-Sleep 15
            }

            $VMAvailabilitySets = Search-AzGraph -Query $graphQuery

            $waitingForARG = $true
        } while ($VMPIPRecords.count -eq 0 -and $env:LBMIG_WAIT_FOR_ARG -and $timeoutStopwatch.Elapsed.Seconds -lt $global:defaultJobWaitTimeout)

        If ($timeoutStopwatch.Elapsed.Seconds -gt $global:defaultJobWaitTimeout) {
            log -Severity Error -Message "[UpgradeVMPublicIP] Resource Graph query timed out before results were returned! The Resource Graph lags behind ARM by several minutes--if the resources to migrate were just created (as in a test), test the query from the log to determine if this was an ingestion lag or synax failure. Once the issue has been corrected follow the steps at https://aka.ms/basiclbupgradefailure to retry the migration." -terminateOnError
        }

        If (($VMAvailabilitySets | Sort-Object | Get-Unique).count -gt 1) {
            log -Severity Error -Message "[Test-SupportedMultiLBScenario] The provided Basic Load Balancers do not share backend pool members (VMs are in differnet Availability Sets). Using -multiLBConfig when backend is not shared adds risk and complexity in recovery." -terminateOnError
        }
        Else {
            log -Message "[Test-SupportedMultiLBScenario] The provided Basic Load Balancers share '$($groupedBackends.count)' backend pool members."
        }
    }


    log -Message "[Test-SupportedMultiLBScenario] Multi-LB configuration is valid for migration"
}

Export-ModuleMember -Function Test-SupportedMigrationScenario, _GetScenarioBackendType, Test-SupportedMultiLBScenario