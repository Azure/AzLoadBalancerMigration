
Function Start-AzAvSetPublicIPUpgrade {
    <#
    .SYNOPSIS
        Upgrades all public IP addresses attached to VMs in an Availability Set to Standard SKU.
    .DESCRIPTION
        This script upgrades the Public IP Addresses attached to VMs in an Availability Set to Standard SKU. In order to perform the upgrade, the Public IP Address
        allocation method is set to static before being disassociated from the VM. Once disassociated, the Public IP SKU is upgraded to Standard,
        then the IP is reassociated with the VM. 

        Because the Public IP allocation is set to 'Static' before detaching from the VM, the IP address will not change during the upgrade process,
        even in the event of a script failure.

        Because Standard SKU Public IPs require an associated Network Security Group, the script will prompt to proceed if a VM is processed where
        both the NIC and subnet do not have an NSG associated with them. If the script is run with the '-ignoreMissingNSG' parameter, the script will
        not prompt and will continue with the upgrade process; if -SkipAVSetMissingNSG is specified, the script will skip upgrading that VM.

        Recovering from a failure:
        The script exports the Public IP address and IP configuration associations to a CSV file before beginning the upgrade process. In the event
        of a failure during the upgrade, this file can be used to retry the migration and attach public IPs with the appropriate IP configuration.
        To initate a recovery, follow these steps:
            1. Review the log 'PublicIPUpgrade.log' file to determine which VM was in process during the failure
            2. Determine if the script failed due to a configuration issue that needs to be addressed before retrying the migration. If so, address the error. 
            2. Get the name and resource group or full ID of the Av Set to recover (e.g. '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/myRG/providers/Microsoft.Compute/availabilitySets/avset-01')
            3. Execute the script with the following syntax:

            ./Start-AzAvSetPublicIPUpgrade.ps1 -RecoverFromFile ./AvSetPublicIPUpgrade_Recovery_2020-01-01-00-00.csv -AvailiabilitySetName avset-01 -ResourceGroupName rg-01
            
            4. The script will attempt to re-execute each step the migration. 
    .NOTES
        PREREQUISITES:
        - VMs must not be associated with a Load Balancer to use this script.
        - VM NICs or associated subnets should have an NSG associated with them. If the VM NIC or subnet does not have an NSG associated with it, the script will prompt.
    .LINK
        https://github.com/Azure/AzLoadBalancerMigration

        Please report issues at https://github.com/Azure/AzLoadBalancerMigration/issues
    .EXAMPLE
        Start-AzAvSetPublicIPUpgrade -AvailabilitySetName 'myAvSet' -ResourceGroupName 'myRG'
        # Upgrade a single Av Set, passing the VM name and resource group name as parameters. 

    .EXAMPLE
        Start-AzAvSetPublicIPUpgrade -AvailabilitySetName 'myAvSet' -ResourceGroupName 'myRG' -WhatIf
        # Evaluate upgrading a single Av Set, without making any changes

    .EXAMPLE
        Get-AzAvailabilitySet -ResourceGroupName 'myRG' | Start-AzAvSetPublicIPUpgrade -SkipAVSetMissingNSG
        # Attempt upgrade of every AV Set the user has access to. VMs without Public IPs, which are already upgraded, or which do not have NSGs will be skipped. 

    .EXAMPLE
        Start-AzAvSetPublicIPUpgrade -RecoverFromFile ./PublicIPUpgrade_Recovery_2020-01-01-00-00.csv -AvailabilitySetName myAvSet -ResourceGroup rg-myrg
        # Recover from a failed migration, passing the name and resource group of the VM to recover, along with the recovery log file.

    .EXAMPLE
        Get-AzAvailabilitySet -ResourceGroupName rg-*-prod | Start-AvSetPublicIPUpgrade -WhatIf

        # Test upgrade on all AvSetss in Resource Groups with '-prod' in the name
#>

    param (
        # av set name
        [Parameter(Mandatory = $true, ParameterSetName = 'AvailabilitySetName')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Recovery-ByName')]
        [string]
        $availabilitySetName,

        # av set resource group name
        [Parameter(Mandatory = $true, ParameterSetName = 'AvailabilitySetName')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Recovery-ByName')]
        [string]
        $resourceGroupName,

        # av set object
        [Parameter(Mandatory = $true, ParameterSetName = 'AVSetObject', ValueFromPipeline = $true)]
        [Microsoft.Azure.Commands.Compute.Models.PSAvailabilitySet]
        $availabilitySet,

        # av set resource id
        [Parameter(Mandatory = $true, ParameterSetName = 'AVSetResourceID')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Recovery-ById')]
        [string]
        $availabilitySetResourceId,

        # recovery file path
        [Parameter(Mandatory = $true, ParameterSetName = 'Recovery-ById')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Recovery-ByName')]
        [string]
        $recoverFromFile,

        # recovery log file path - log Public IP address and IP configuration associations for recovery purposes
        [Parameter(Mandatory = $false)]
        [string]
        $recoveryLogFilePath = "AvSetPublicIPUpgrade_Recovery_$(Get-Date -Format 'yyyy-MM-dd-HH-mm').csv",

        # log file path
        [Parameter(Mandatory = $false)]
        [string]
        $logFilePath = "AvSetPublicIPUpgrade.log",

        # skip check for NSG association, migrate anyway - Basic Public IPs allow inbound traffic without an NSG, but Standard Public IPs require an NSG. Migrating without an NSG will break inbound traffic flows!    
        [Parameter(Mandatory = $false)]
        [switch]
        $ignoreMissingNSG,

        # skip Availabiltiy Sets where VMs are missing NSGs - if a VM is missing an NSG, skip migrating all VMs in the Availability Set
        [Parameter(Mandatory = $false)]
        [switch]
        $SkipAVSetMissingNSG,

        # prompt for confirmation to migrate IPs
        [Parameter(Mandatory = $false)]
        [boolean]
        $confirm = $true,

        # whatif
        [Parameter(Mandatory = $false)]
        [switch]
        $WhatIf
    )

    BEGIN {
        Function Add-LogEntry {
            param (
                [parameter(Position = 0, Mandatory = $true)]$message,
                [parameter(Position = 1, Mandatory = $false)][ValidateSet('INFO', 'WARNING', 'ERROR')]$severity = 'INFO'
            )

            # add timestamp to message, output to log and host
            $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszz'
            switch ($severity) {
                'INFO' { "[{0}][{1}] {2}" -f $timestamp, $severity, $message | Tee-Object -FilePath $logFilePath -Append | Write-Host }
                'WARNING' { "[{0}][{1}] {2}" -f $timestamp, $severity, $message | Tee-Object -FilePath $logFilePath -Append | Write-Warning }
                'ERROR' { "[{0}][{1}] {2}" -f $timestamp, $severity, $message | Tee-Object -FilePath $logFilePath -Append | Write-Error }
            }
        }

        # set error action preference 
        If ($WhatIf) { $ErrorActionPreference = 'Continue' }
        Else { $ErrorActionPreference = 'Stop' }
        
        Add-LogEntry "####### Starting Availability Set Public IP Upgrade validation process #######"

        # prompt to continue if -Confirm is $false or -WhatIf are not specified
        If (!$WhatIf -and $confirm) {
            While ($promptResponse -notmatch '[yYnN]') {
                $promptResponse = Read-Host "This script will upgrade all public IP addresses attached to all VMs in the specificed Availability Set(s) to Standard SKU. This will cause a brief interruption to network connectivity. Do you want to continue? (y/n)"
            }
        
            If ($promptResponse -match '[nN]') {
                Add-LogEntry "Exiting script..." -severity WARNING
                return
            }
            Else {
                Add-LogEntry "Continuing with script..."
            }
        }

        # initalize recovery log file header
        Add-Content -Path $recoveryLogFilePath -Value 'publicIPAddress,publicIPID,ipConfigId,VMId,availabilitySetResourceId' -Force

        Add-LogEntry "Creating recovery log file at '$($recoveryLogFilePath)'"
    }

    PROCESS {
        # get avset object, depending on parameters passed
        If ($PSCmdlet.ParameterSetName -in 'AvailabilitySetName', 'Recovery-ByName') {
            Add-LogEntry "Getting Availability Set '$($AvailabilitySetName)' in resource group '$($resourceGroupName)'..."
            $AvSet = Get-AzAvailabilitySet -Name $availabilitySetName -ResourceGroupName $resourceGroupName
        }
        ElseIf ($PSCmdlet.ParameterSetName -in 'AVSetResourceID', 'Recovery-ById') {
            Add-LogEntry "Getting Availability Set with resource ID '$($availabilitySetResourceId)'..."
            $AvSet = Get-AzResource -ResourceId $availabilitySetResourceId | Get-AzAvailabilitySet
        }
        Else {
            $AvSet = $availabilitySet
        }

        Add-LogEntry "Processing Availability Set '$($AvSet.Name)', id: $($AvSet.Id)..."
        # validate scenario

        # get all VMs in the availability set
        # check that availabilit set has vms
        If ($AvSet.VirtualMachinesReferences.count -lt 1) {
            Add-LogEntry "Availability Set '$($AvSet.Name)' does not have any VMs. Skipping upgrade." -severity WARNING
            return
        }

        $VMs = @()
        Add-LogEntry "Getting all VMs in Availability Set '$($AvSet.Name)'..."

        # create array of VM objects
        $avSet.VirtualMachinesReferences.Id | ForEach-Object {
            $VM = $_ | Get-AzVM
            $VMs += @{vmObject = $VM; vmNICs = @(); publicIPs = @(); publicIPIPConfigAssociations = @() } 
        }

        If ($PSCmdlet.ParameterSetName -notin 'Recovery-ByName', 'Recovery-ById') {
            ForEach ($VM in $VMs) {
                Add-LogEntry "Validating VM '$($VM.vmObject.Name)' in Availability Set '$($AvSet.Name)'..."

                # confirm VM has public IPs attached, build dictionary of public IPs and ip configurations
                Add-LogEntry "Checking that VM '$($VM.vmObject.Name)' has public IP addresses attached..."

                ## get NICs with public IPs attached
                $VM.vmNICs = $VM.vmObject.NetworkProfile.NetworkInterfaces | Get-AzResource | Get-AzNetworkInterface | Where-Object { $_.IpConfigurations.PublicIPAddress }

                ## build ipconfig/public IP table
                $publicIPIDs = @()
                $VM.publicIPIPConfigAssociations = @()
                ForEach ($ipConfig in $VM.vmNICs.IpConfigurations) {
                    If ($ipConfig.PublicIPAddress) {
                        $publicIPIDs += $ipConfig.PublicIPAddress.id
                        $VM.publicIPIPConfigAssociations += @{
                            publicIPId      = $ipConfig.PublicIPAddress.id
                            ipConfig        = $ipConfig
                            publicIP        = ''
                            publicIPAddress = ''
                        }
                    }
                }

                If ($VM.publicIPIPConfigAssociations.count -lt 1) {
                    Add-LogEntry "VM '$($VM.vmObject.Name)' does not have any public IP addresses attached. Skipping upgrading this VM." -severity INFO
                    $VMs = $VMs | Where-Object { $_.vmObject.Id -ne $VM.vmObject.Id }
                    continue
                }
                Else {
                    Add-LogEntry "VM '$($VM.vmObject.Name)' has $($VM.publicIPIPConfigAssociations.count) public IP addresses attached."
                }
    
                # confirm public IPs are Basic SKU (VM should only have one SKU)
                Add-LogEntry "Checking that VM '$($VM.vmObject.Name)' has Basic SKU public IP addresses..."
                $VM.publicIPs = $publicIPIDs | ForEach-Object { Get-AzResource -ResourceId $_ | Get-AzPublicIpAddress }
                If (( $publicIPSKUs = $VM.publicIPs.Sku.Name | Get-Unique) -ne @('Basic')) {
                    Add-LogEntry "Public IP address SKUs for VM '$($VM.vmObject.Name)' are not Basic. SKUs are: '$($publicIPSKUs -join ',')'. Skipping upgrade." WARNING
                    return
                }
                Else {
                    Add-LogEntry "Public IP address SKUs for VM '$($VM.vmObject.Name)' are Basic."
                }

                # confirm VM is not associated with a load balancer
                Add-LogEntry "Checking that VM '$($VM.vmObject.Name)' is not associated with a load balancer..."
                If ($VM.vmNICs.IpConfigurations.LoadBalancerBackendAddressPools -or $VM.vmNICs.IpConfigurations.LoadBalancerInboundNatRules) {
                    Add-LogEntry "VM '$($VM.vmObject.Name)' is associated with a load balancer. The Load Balancer cannot be a different SKU from the VMs' Public IP address(s) and must be upgraded simultaneously. See: https://learn.microsoft.com/azure/load-balancer/load-balancer-basic-upgrade-guidance" ERROR
                    return
                }
                Else {
                    Add-LogEntry "VM '$($VM.vmObject.Name)' is not associated with a load balancer."
                }

                # check that public IPs are IPv4, as IPv6 can't be set to static [it is not currently possible to create a Basic SKU IPv6 Public IP]
                Add-LogEntry "Checking that VM '$($VM.vmObject.Name)' has IPv4 public IP addresses..."
                If ($VM.publicIPs.publicIPAddressVersion -contains 'IPv6') {
                    Add-LogEntry "Public IP addresses for VM '$($VM.vmObject.Name)' are IPv6. IPv6 Public IP addresses cannot be set to static. Skipping upgrade." WARNING
                    return
                }
                Else {
                    Add-LogEntry "Public IP addresses for VM '$($VM.vmObject.Name)' are IPv4."
                }

                # confirm that each NIC with a public IP address associated has a Network Security Group
                Add-LogEntry "Checking that VM '$($VM.vmObject.Name)' has a Network Security Group associated with each NIC..."
        
                ## build hash of subnets associated with VM NICs
                $VMNICSubnets = @{}
                ForEach ($nic in $VM.vmNICs) {
                    ForEach ($subnetId in $nic.IpConfigurations.Subnet.id) {
                        $subnet = Get-AzResource -ResourceId $subnetId | Get-AzVirtualNetworkSubnetConfig
                        $VMNICSubnets[$subnet.id] = $subnet
                    }
                }

                ## check that each NIC or all subnets have NSGs associated
                $nicsMissingNSGs = 0
                $ipConfigNSGReport = @()
                ForEach ($vmNIC in $VM.vmNICs) {
                    Add-LogEntry "Checking NIC '$($vmNIC.Name)' for associated Network Security Group..."

                    $ipconfigSubnetsWithoutNSGs = 0
                    $ipconfigSubnetNSGs = @()
                    ForEach ($ipconfig in $vmNIC.IpConfigurations) {
                        If ($VMNICSubnets[$ipconfig.Subnet.id].NetworkSecurityGroup) {
                            Add-LogEntry "NIC '$($vmNIC.Name)' has a Network Security Group associated with subnet '$($VMNICSubnets[$ipconfig.Subnet.id].Name)'."
                            $ipconfigSubnetNSGs += @{
                                ipConfigId   = $ipconfig.id 
                                subnetId     = $ipconfig.Subnet.Id
                                subnetHasNSG = $true # <-----------------------
                                subnetNSGID  = $VMNICSubnets[$ipconfig.Subnet.id].NetworkSecurityGroup.id
                                nicHasNSG    = $null -ne $vmNIC.NetworkSecurityGroup
                                nicNSGId     = $vmNIC.NetworkSecurityGroup.id
                            }
                        }
                        Else {
                            Add-LogEntry "NIC '$($vmNIC.Name)' does not have a Network Security Group associated with subnet '$($VMNICSubnets[$ipconfig.Subnet.id].Name)'."
                            $ipconfigSubnetsWithoutNSGs++
                            $ipconfigSubnetNSGs += @{
                                ipConfigId   = $ipconfig.id 
                                subnetId     = $ipconfig.Subnet.Id
                                subnetHasNSG = $false # <-----------------------
                                subnetNSGId  = $null
                                nicHasNSG    = $null -ne $vmNIC.NetworkSecurityGroup
                                nicNSGId     = $vmNIC.NetworkSecurityGroup.id
                            }
                        }
                    }

                    If ($ipconfigSubnetsWithoutNSGs -gt 0 -and !$vmNIC.NetworkSecurityGroup) {
                        $ipConfigNSGReport += $ipconfigSubnetNSGs
                        $nicsMissingNSGs++
                    }
                }

                If ($nicsMissingNSGs -gt 0) {
                    Add-LogEntry "VM '$($VM.vmObject.Name)' has associated Public IP Addresses, but IP Configurations where neither the NIC nor Subnet have an associated Network Security Group. Standard SKU Public IPs are secure by default, meaning no inbound traffic is allowed unless an NSG explicitly permits it, whereas a Basic SKU Public IP allows all traffic by default. See: https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/public-ip-addresses#sku." WARNING
                    Add-LogEntry "IP Configs Missing NGSs Report: $($ipConfigNSGReport | ConvertTo-Json -Depth 3)" WARNING
            
                    While ($promptResponse -notmatch '[yYnN]' -and !$ignoreMissingNSG -and !$SkipAVSetMissingNSG) {
                        If ($WhatIf) {
                            Add-LogEntry "SKIPPED PROMPT: 'Do you want to proceed with upgrading this VM's Public IP address without an NSG? (y/n):' **Assuming 'n' because -WhatIf was specified**" WARNING
                            $promptResponse = 'n'
                        }
                        Else {
                            $promptResponse = Read-Host "Do you want to proceed with upgrading this VM's Public IP address without an NSG? (y/n)"
                        }
                    }
            
                    If ($promptResponse -match '[nN]' -or $SkipAVSetMissingNSG) {
                        Add-LogEntry "Skipping migrating this Availability Set due to VM '$($VM.vmObject.Name)' missing NSG..." -severity WARNING
                        return
                    }
                    ElseIf ($ignoreMissingNSG) {
                        Add-LogEntry "Skipping NSG check because -ignoreMissingNSG was specified" WARNING
                    }
                    Else {
                        Add-LogEntry "Continuing with script, ignoring missing NSGs..."
                    }
                }
                Else {
                    Add-LogEntry "VM '$($VM.vmObject.Name)' has a Network Security Group associated with each NIC or subnet."
                }
        
            }
        }
        Else {
            ### Failed Migration Recovery ###
            # import recovery info
            Add-LogEntry "Importing recovery file for Availability Set '$($AvSet.Name)' from file '$($recoverFromFile)'"

            $recoveryInfo = Import-Csv -path $recoverFromFile | Where-Object { $_.availabilitySetResourceId -eq $AvSet.Id }

            $VMs = @()
            ForEach ($vmRecoveryItem in ($recoveryInfo | Group-Object -Property VMId).group) {

                Add-LogEntry "Building recovery objects for VM '$($vmRecoveryItem.VMId.split('/')[-1])' based on recovery file '$($recoverFromFile)'..."
                $VM = @{
                    vmObject = Get-AzVM -ResourceId $vmRecoveryItem.VMId
                    publicIPIDs = $vmRecoveryItem.PublicIPID
                    vmNICs = @()
                    vmNICsById = @{}
                    publicIPIPConfigAssociations = @()
                }
                # rebuild migration objects from recovery to retry

                $vmRecoveryItem.ipConfigId | 
                ForEach-Object { ($_ -split '/ipConfigurations/')[0] } | Select-Object -Unique | ForEach-Object { $_ | Get-AzNetworkInterface } |
                ForEach-Object { 
                    $VM.vmNICs += $_ 
                    $VM.vmNICsById[$_.id] = $_
                }

                ForEach ($recoveryItem in $vmRecoveryItem) {
                    $ipConfigSplit = $recoveryItem.ipConfigId -split '/ipConfigurations/'
                    $publicIPIDs += $ipConfig.PublicIPAddress.id
                    $VM.publicIPIPConfigAssociations += @{
                        publicIPId      = $recoveryItem.publicIPID
                        ipConfig        = Get-AzNetworkInterfaceIpConfig -NetworkInterface $VM.vmNICsById[$ipConfigSplit[0]] -Name $ipConfigSplit[1]
                        publicIP        = Get-AzResource -ResourceId $recoveryItem.publicIPID | Get-AzPublicIpAddress
                        publicIPAddress = $recoveryItem.publicIPAddress
                    }
                }

                $VM.publicIPs = $VM.publicIPIPConfigAssociations.publicIP

                $VMs += $VM
            }    
        }

        # start prepare upgrade process
        Add-LogEntry "####### Starting prepare upgrade process... #######"
        ForEach ($VM in $VMs) {
            Add-LogEntry "Backing up config for VM '$($VM.vmObject.Name)' to '$recoveryLogFilePath'.."
            # export recovery data and add public ip object to association object
            ForEach ($publicIP in $VM.publicIPs) {
                $VM.publicIPIPConfigAssociations | Where-Object { $_.publicIPId -eq $publicIP.id } | ForEach-Object { 
                    $_.publicIPAddress = $VM.publicIP.IpAddress
                    $_.publicIP = $publicIP 
            
                    Add-Content -Path $recoveryLogFilePath -Value ('{0},{1},{2},{3},{4}' -f $publicIP.IPAddress, $_.publicIPId, $_.ipConfig.id, $VM.vmObject.Id, $AvSet.id) -Force
                }
            }
        }

        ForEach ($VM in $VMs) {
            Add-LogEntry "--> Preparing VM '$($VM.vmObject.Name)' for upgrade..."
            try {
                # set all public IPs to static assignment
                Add-LogEntry "Setting all public IP addresses to static assignment..."
                ForEach ($publicIP in $VM.publicIPIPConfigAssociations.publicIP) {
                    Add-LogEntry "Setting public IP address '$($publicIP.Name)' ('$($publicIP.IpAddress)') to static assignment..."
                    $publicIP.PublicIpAllocationMethod = 'Static'

                    If (!$WhatIf) {
                        $publicIP = Set-AzPublicIpAddress -PublicIpAddress $publicIP
                    }
                    Else {
                        Add-LogEntry "WhatIf: Set-AzPublicIpAddress -PublicIpAddress $($publicIP.id)"
                    }
                }

                # disassociate all public IPs from the VM
                Add-LogEntry "Disassociating all public IP addresses from the VM..."
                Foreach ($nic in $VM.vmNICs) {
                    ForEach ($ipConfig in $nic.IpConfigurations | Where-Object { $_.PublicIPAddress }) {
                        Add-LogEntry "Confirming that Public IP allocation is 'static' before disassociating..."
                        If ((Get-AzResource -ResourceId $ipConfig.PublicIpAddress.Id | Get-AzPublicIpAddress).PublicIpAllocationMethod -ne 'Static') {
                            If (!$WhatIf) {
                                Write-Error "Public IP address '$($ipConfig.PublicIpAddress.Id)' is not set to static allocation! Script will exit to ensure that the VM's public IP addresses are not lost."
                                return
                            }
                            Else {
                                Add-LogEntry "WhatIf: Public IP address '$($ipConfig.PublicIpAddress.Id)' not changed from 'Dynamic' in WhatIf mode."
                            }
                        }

                        If (!$WhatIf) {
                            Add-LogEntry "Disassociating public IP address '$($ipConfig.PublicIpAddress.Id)' from VM '$($VM.vmObject.Name)', NIC '$($nic.Name)'..."
                            Set-AzNetworkInterfaceIpConfig -NetworkInterface $nic -Name $ipConfig.Name -PublicIpAddress $null | Out-Null
                        }
                        Else {
                            Add-LogEntry "WhatIf: Disassociating public IP address '$($ipConfig.PublicIpAddress.Id)' from VM '$($VM.vmObject.Name)', NIC '$($nic.Name)'..."
                        }
                    }

                    Add-LogEntry "Applying updates to the NIC '$($nic.Name)'..."
                    If (!$WhatIf) {
                        $nic | Set-AzNetworkInterface | Out-Null
                    }
                    Else {
                        Add-LogEntry "WhatIf: Updating NIC with: `$nic | Set-AzNetworkInterface"
                    }
                }
            }
            catch {
                Write-Error "An error occurred during the prepare upgrade process. $_"
            }
        }

        #start upgrade process
        Add-LogEntry "####### Starting upgrade process #######"
        ForEach ($VM in $VMs) {
            Add-LogEntry "--> Starting upgrade process for VM '$($VM.vmObject.Name)'..."
            try {
                # upgrade all public IP addresses
                Add-LogEntry "Upgrading all public IP addresses to Standard SKU..."
                ForEach ($publicIP in $VM.publicIPIPConfigAssociations.publicIP) {
                    Add-LogEntry "Upgrading public IP address '$($publicIP.Name)' to Standard SKU..."
                    $publicIP.Sku.Name = 'Standard'

                    If (!$WhatIf) {
                        Set-AzPublicIpAddress -PublicIpAddress $publicIP | Out-Null
                    }
                    Else {
                        Add-LogEntry "WhatIf: Set-AzPublicIpAddress -PublicIpAddress $($_.id)"
                    }
                }
            }
            catch {
                Write-Error "An error occurred during the upgrade process. We will try to reassociate all IPs with the VM: $_"
            }
            finally {
                # always reassociate all public IPs to the VM
                Add-LogEntry "Reassociating all public IP addresses to the VM..."

                try {
                    Foreach ($nic in $VM.vmNICs) {
                        Add-LogEntry "Reassociating public IP addresses to VM '$($VM.vmObject.Name)', NIC '$($nic.Name)'..."
                        ForEach ($association in ($VM.publicIPIPConfigAssociations | Where-Object { $_.ipconfig.Id -like "$($nic.Id)/*" })) {
                            Add-LogEntry "Reassociating public IP address '$($association.publicIPId)' to VM '$($VM.vmObject.Name)', NIC '$($nic.Name)', IpConfig '$($association.ipconfig.Name)'..."
                            Set-AzNetworkInterfaceIpConfig -NetworkInterface $nic -Name $association.ipConfig.Name -PublicIpAddress $association.publicIP | Out-Null
                        }

                        Add-LogEntry "Applying updates to the NIC '$($nic.Name)'..."
                        If (!$WhatIf) {
                            $nic | Set-AzNetworkInterface | Out-Null
                        }
                        Else {
                            Add-LogEntry "WhatIf: Updating NIC with: `$nic | Set-AzNetworkIntereface"
                        }
                    }
                }
                catch {
                    Add-LogEntry "An error occurred while reassociating public IP addresses to the VM: $_" ERROR
                }
            }

            Add-LogEntry "Upgrade of VM '$($VM.vmObject.Name)' complete.'"
        }

        Add-LogEntry "Upgrade of Availability Set '$($AvSet.Name)' complete.'"
    }

    END {
        Add-LogEntry "####### Upgrade process complete. #######"
    }
}