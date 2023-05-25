
Function Start-VMPublicIPUpgrade {
    <#
    .SYNOPSIS
        Upgrades all public IP addresses attached to a VM to Standard SKU.
    .DESCRIPTION
        This script upgrades the Public IP Addresses attached to VM to Standard SKU. In order to perform the upgrade, the Public IP Address
        allocation method is set to static before being disassociated from the VM. Once disassociated, the Public IP SKU is upgraded to Standard,
        then the IP is reassociated with the VM. 

        Because the Public IP allocation is set to 'Static' before detaching from the VM, the IP address will not change during the upgrade process,
        even in the event of a script failure.

        Because Standard SKU Public IPs require an associated Network Security Group, the script will prompt to proceed if a VM is processed where
        both the NIC and subnet do not have an NSG associated with them. If the script is run with the '-ignoreMissingNSG' parameter, the script will
        not prompt and will continue with the upgrade process; if -skipVMMissingNSG is specified, the script will skip upgrading that VM.

        Recovering from a failure:
        The script exports the Public IP address and IP configuration associations to a CSV file before beginning the upgrade process. In the event
        of a failure during the upgrade, this file can be used to retry the migration and attach public IPs with the appropriate IP configuration.
        To initate a recovery, follow these steps:
            1. Review the log 'PublicIPUpgrade.log' file to determine which VM was in process during the failure
            2. Determine if the script failed due to a configuration issue that needs to be addressed before retrying the migration. If so, address the error. 
            2. Get the name and resource group or full ID of the VM to recover (e.g. '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/myRG/providers/Microsoft.Compute/virtualMachines/myVM')
            3. Execute the script with the following syntax:

            ./Start-VMPublicIPUpgrade.ps1 -RecoverFromFile ./PublicIPUpgrade_Recovery_2020-01-01-00-00.csv -VMResourceId '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/myRG/providers/Microsoft.Compute/virtualMachines/myVM'
            
            4. The script will attempt to re-execute each step the migration. 
    .NOTES
        PREREQUISITES:
        - VMs must not be associated with a Load Balancer to use this script.
        - VM NICs or associated subnets should have an NSG associated with them. If the VM NIC or subnet does not have an NSG associated with it, the script will prompt.
    .LINK
        https://github.com/Azure/AzLoadBalancerMigration

        Please report issues at https://github.com/Azure/AzLoadBalancerMigration/issues
    .EXAMPLE
        Start-VMPublicIPUpgrade -VMName 'myVM' -ResourceGroupName 'myRG'
        # Upgrade a single VM, passing the VM name and resource group name as parameters. 

    .EXAMPLE
        Start-VMPublicIPUpgrade -VMName 'myVM' -ResourceGroupName 'myRG' -WhatIf
        # Evaluate upgrading a single VM, without making any changes

    .EXAMPLE
        Get-AzVM -ResourceGroupName 'myRG' | Start-VMPublicIPUpgrade -skipVMMissingNSG
        # Attempt upgrade of every VM the user has access to. VMs without Public IPs, which are already upgraded, or which do not have NSGs will be skipped. 

    .EXAMPLE
        Start-VMPublicIPUpgrade -RecoverFromFile ./PublicIPUpgrade_Recovery_2020-01-01-00-00.csv -VMName myVM -VMResourceGroup -rg-myrg
        # Recover from a failed migration, passing the name and resource group of the VM to recover, along with the recovery log file.

    .EXAMPLE
        $VMs = Get-AzVM -ResourceGroupName rg-*-prod
        ForEach ($vm in $VMs) {
            Start-Job -Name $vm.Name -ScriptBlock {
                $params = @{
                    vmName = $args[0].Name
                    resourceGroupName = $args[0].ResourceGroupName
                    logFilePath = '{0}{1}' -f $args[0].Name,'name_PublicIPUpgrade.log'
                    recoveryLogFilePath = '{0}{1}' -f $args[0].Name,'name_PublicIPUpgrade_recovery.csv'
                }
                Start-VMPublicIPUpgrade.ps1 @params -WhatIf
            } -ArgumentList $vm -InitializationScript {Import-Module Az.Accounts, Az.Compute, Az.Network, Az.Resources}
        }
        # Upgrade all VMs in Resource Groups with '-prod' in the name, using PowerShell jobs to run the script in parallel.
#>

    param (
        # vm name
        [Parameter(Mandatory = $true, ParameterSetName = 'VMName')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Recovery-ByName')]
        [string]
        $vmName,

        # vm resource group name
        [Parameter(Mandatory = $true, ParameterSetName = 'VMName')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Recovery-ByName')]
        [string]
        $resourceGroupName,

        # vm object
        [Parameter(Mandatory = $true, ParameterSetName = 'VMObject', ValueFromPipeline = $true)]
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]
        $VM,

        # vm resource id
        [Parameter(Mandatory = $true, ParameterSetName = 'VMResourceId')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Recovery-ById')]
        [string]
        $vmResourceId,

        # vm resource id
        [Parameter(Mandatory = $true, ParameterSetName = 'Recovery-ById')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Recovery-ByName')]
        [string]
        $recoverFromFile,

        # recovery log file path - log Public IP address and IP configuration associations for recovery purposes
        [Parameter(Mandatory = $false)]
        [string]
        $recoveryLogFilePath = "PublicIPUpgrade_Recovery_$(Get-Date -Format 'yyyy-MM-dd-HH-mm').csv",

        # log file path
        [Parameter(Mandatory = $false)]
        [string]
        $logFilePath = "PublicIPUpgrade.log",

        # skip check for NSG association, migrate anyway - Basic Public IPs allow inbound traffic without an NSG, but Standard Public IPs require an NSG. Migrating without an NSG will break inbound traffic flows!    
        [Parameter(Mandatory = $false)]
        [switch]
        $ignoreMissingNSG,

        # skip VMs missing NSGs - if a VM is missing an NSG, skip migrating it
        [Parameter(Mandatory = $false)]
        [switch]
        $skipVMMissingNSG,

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
        
        Add-LogEntry "####### Starting VM Public IP Upgrade process... #######"

        # prompt to continue if -Confirm is $false or -WhatIf are not specified
        If (!$WhatIf -and $confirm) {
            While ($promptResponse -notmatch '[yYnN]') {
                $promptResponse = Read-Host "This script will upgrade all public IP addresses attached to the specified VM or VMs to Standard SKU. This will cause a brief interruption to network connectivity. Do you want to continue? (y/n)"
            }
        
            If ($promptResponse -match '[nN]') {
                Add-LogEntry "Exiting script..." -severity WARNING
                Exit
            }
            Else {
                Add-LogEntry "Continuing with script..."
            }
        }

        # initalize recovery log file header
        Add-Content -Path $recoveryLogFilePath -Value 'publicIPAddress,publicIPID,ipConfigId,VMId' -Force

        Add-LogEntry "Creating recovery log file at '$($recoveryLogFilePath)'"
    }

    PROCESS {
        # get vm object, depending on parameters passed
        If ($PSCmdlet.ParameterSetName -in 'VMName', 'Recovery-ByName') {
            Add-LogEntry "Getting VM '$($VMName)' in resource group '$($resourceGroupName)'..."
            $VM = Get-AzVM -Name $vmName -ResourceGroupName $resourceGroupName
        }
        ElseIf ($PSCmdlet.ParameterSetName -in 'VMResourceId', 'Recovery-ById') {
            Add-LogEntry "Getting VM with resource ID '$($vmResourceId)'..."
            $VM = Get-AzResource -ResourceId $vmResourceId | Get-AzVM
        }

        Add-LogEntry "Processing VM '$($VM.Name)', id: $($VM.Id)..."
        # validate scenario

        If ($PSCmdlet.ParameterSetName -notin 'Recovery-ByName', 'Recovery-ById') {
            # confirm VM has public IPs attached, build dictionary of public IPs and ip configurations
            Add-LogEntry "Checking that VM '$($VM.Name)' has public IP addresses attached..."

            ## get NICs with public IPs attached
            $vmNICs = $VM.NetworkProfile.NetworkInterfaces | Get-AzResource | Get-AzNetworkInterface | Where-Object { $_.IpConfigurations.PublicIPAddress }

            ## build ipconfig/public IP table
            $publicIPIDs = @()
            $publicIPIPConfigAssociations = @()
            ForEach ($ipConfig in $vmNICs.IpConfigurations) {
                If ($ipConfig.PublicIPAddress) {
                    $publicIPIDs += $ipConfig.PublicIPAddress.id
                    $publicIPIPConfigAssociations += @{
                        publicIPId      = $ipConfig.PublicIPAddress.id
                        ipConfig        = $ipConfig
                        publicIP        = ''
                        publicIPAddress = ''
                    }
                }
            }

            If ($publicIPIPConfigAssociations.count -lt 1) {
                Add-LogEntry "VM '$($VM.Name)' does not have any public IP addresses attached. Skipping upgrade." -severity WARNING
                return
            }
            Else {
                Add-LogEntry "VM '$($VM.Name)' has $($publicIPIPConfigAssociations.count) public IP addresses attached."
            }
    
            # confirm public IPs are Basic SKU (VM should only have one SKU)
            Add-LogEntry "Checking that VM '$($VM.Name)' has Basic SKU public IP addresses..."
            $publicIPs = $publicIPIDs | ForEach-Object { Get-AzResource -ResourceId $_ | Get-AzPublicIpAddress }
            If (( $publicIPSKUs = $publicIPs.Sku.Name | Get-Unique) -ne @('Basic')) {
                Add-LogEntry "Public IP address SKUs for VM '$($VM.Name)' are not Basic. SKUs are: '$($publicIPSKUs -join ',')'. Skipping upgrade." WARNING
                return
            }
            Else {
                Add-LogEntry "Public IP address SKUs for VM '$($VM.Name)' are Basic."
            }

            # confirm VM is not associated with a load balancer
            Add-LogEntry "Checking that VM '$($VM.Name)' is not associated with a load balancer..."
            If ($VMNICs.IpConfigurations.LoadBalancerBackendAddressPools -or $VMNICs.IpConfigurations.LoadBalancerInboundNatRules) {
                Add-LogEntry "VM '$($VM.Name)' is associated with a load balancer. The Load Balancer cannot be a different SKU from the VM's Public IP address(s) and must be upgraded simultaneously. See: https://learn.microsoft.com/azure/load-balancer/load-balancer-basic-upgrade-guidance" ERROR
                return
            }
            Else {
                Add-LogEntry "VM '$($VM.Name)' is not associated with a load balancer."
            }

            # confirm that each NIC with a public IP address associated has a Network Security Group
            Add-LogEntry "Checking that VM '$($VM.Name)' has a Network Security Group associated with each NIC..."
        
            ## build hash of subnets associated with VM NICs
            $VMNICSubnets = @{}
            ForEach ($nic in $vmNICs) {
                ForEach ($subnetId in $nic.IpConfigurations.Subnet.id) {
                    $subnet = Get-AzResource -ResourceId $subnetId | Get-AzVirtualNetworkSubnetConfig
                    $VMNICSubnets[$subnet.id] = $subnet
                }
            }

            ## check that each NIC or all subnets have NSGs associated
            $nicsMissingNSGs = 0
            $ipConfigNSGReport = @()
            ForEach ($vmNIC in $vmNICs) {
                $ipconfigSubnetsWithoutNSGs = 0
                $ipconfigSubnetNSGs = @()
                ForEach ($ipconfig in $vmNIC.IpConfigurations) {
                    If ($VMNICSubnets[$ipconfig.Subnet.id].NetworkSecurityGroup) {
                        $ipconfigSubnetNSGs += @{
                            ipConfigId   = $ipconfig.id 
                            subnetId     = $ipconfig.Subnet.Id
                            subnetHasNSG = $true
                            subnetNSGID  = $VMNICSubnets[$ipconfig.Subnet.id].NetworkSecurityGroup.id
                            nicHasNSG    = $null -ne $vmNIC.NetworkSecurityGroup
                            nicNSGId     = $vmNIC.NetworkSecurityGroup.id
                        }
                    }
                    Else {
                        $ipconfigSubnetsWithoutNSGs++
                        $ipconfigSubnetNSGs += @{
                            ipConfigId   = $ipconfig.id 
                            subnetId     = $ipconfig.Subnet.Id
                            subnetHasNSG = $false
                            subnetNSGId  = ''
                            nicHasNSG    = $null -ne $vmNIC.NetworkSecurityGroup
                            nicNSGId     = $vmNIC.NetworkSecurityGroup.id
                        }
                    }
                }

                If ($ipconfigSubnetsWithoutNSGs -gt 0 -and !$vmNIC.NetworkSecurityGroup) {
                    $ipCOnfigNSGReport += $ipconfigSubnetNSGs
                    $nicsMissingNSGs++
                }
            }

            If ($nicsMissingNSGs -gt 0) {
                Add-LogEntry "VM '$($VM.Name)' has associated Public IP Addresses, but IP Configurations where neither the NIC nor Subnet have an associated Network Security Group. Standard SKU Public IPs are secure by default, meaning no inbound traffic is allowed unless an NSG explicitly permits it, whereas a Basic SKU Public IP allows all traffic by default. See: https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/public-ip-addresses#sku." WARNING
                Add-LogEntry "IP Configs Missing NGSs Report: $($ipConfigNSGReport | ConvertTo-Json -Depth 3)" WARNING
            
                While ($promptResponse -notmatch '[yYnN]' -and !$ignoreMissingNSG -and !$skipVMMissingNSG) {
                    $promptResponse = Read-Host "Do you want to proceed with upgrading this VM's Public IP address without an NSG? (y/n)"
                }
            
                If ($promptResponse -match '[nN]' -or $skipVMMissingNSG) {
                    Add-LogEntry "Skipping migrating this VM due to missing NSG..." -severity WARNING
                    return
                }
                ElseIf ($ignoreMissingNSG) {
                    Add-LogEntry "Skipping NSG check because -ignoreMissingNSG was specified" WARNING
                }
                Else {
                    Add-LogEntry "Continuing with script..."
                }
            }
            Else {
                Add-LogEntry "VM '$($VM.Name)' has a Network Security Group associated with each NIC or subnet."
            }
        
        }
        Else {
            ### Failed Migration Recovery ###
            # import recovery info
            Add-LogEntry "Importing recovery file for VM '$($VM.Name)' from file '$($recoverFromFile)'"

            $recoveryInfo = Import-Csv -path $recoverFromFile | Where-Object { $_.VMId -eq $VM.Id }

            Add-LogEntry "Building recovery objects for VM '$($VM.Name)' based on recovery file '$($recoverFromFile)'..."
            # rebuild migration objects from recovery to retry
            $publicIPIDs = $recoveryInfo.PublicIPID

            $vmNICs = @()
            $vmNICsById = @{}
            $recoveryInfo.ipConfigId | 
            ForEach-Object { ($_ -split '/ipConfigurations/')[0] } | Select-Object -Unique | ForEach-Object { $_ | Get-AzNetworkInterface } |
            ForEach-Object { 
                $vmNICs += $_ 
                $vmNICsById[$_.id] = $_
            }

            $publicIPIPConfigAssociations = @()
            ForEach ($recoveryItem in $recoveryInfo) {
                $ipConfigSplit = $recoveryItem.ipConfigId -split '/ipConfigurations/'
                $publicIPIDs += $ipConfig.PublicIPAddress.id
                $publicIPIPConfigAssociations += @{
                    publicIPId      = $recoveryItem.publicIPID
                    ipConfig        = Get-AzNetworkInterfaceIpConfig -NetworkInterface $vmNICsById[$ipConfigSplit[0]] -Name $ipConfigSplit[1]
                    publicIP        = Get-AzResource -ResourceId $recoveryItem.publicIPID | Get-AzPublicIpAddress
                    publicIPAddress = $recoveryItem.publicIPAddress
                }
            }

            $publicIPs = $publicIPIPConfigAssociations.publicIP
        }

        # start upgrade process
        # export recovery data and add public ip object to assocation object
        ForEach ($publicIP in $publicIPs) {
            $publicIPIPConfigAssociations | Where-Object { $_.publicIPId -eq $publicIP.id } | ForEach-Object { 
                $_.publicIPAddress = $publicIP.IpAddress
                $_.publicIP = $publicIP 
            
                Add-Content -Path $recoveryLogFilePath -Value ('{0},{1},{2},{3}' -f $_.publicIPAddress, $_.publicIPId, $_.ipConfig.id, $VM.Id) -Force
            }
        }

        try {
            # set all public IPs to static assignment
            Add-LogEntry "Setting all public IP addresses to static assignment..."
            ForEach ($publicIP in $publicIPIPConfigAssociations.publicIP) {
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
            Foreach ($nic in $vmNICs) {
                ForEach ($ipConfig in $nic.IpConfigurations | Where-Object { $_.PublicIPAddress }) {
                    Add-LogEntry "Confirming that Public IP allocation is 'static' before disassociating..."
                    If ((Get-AzResource -ResourceId $ipConfig.PublicIpAddress.Id | Get-AzPublicIpAddress).PublicIpAllocationMethod -ne 'Static') {
                        Write-Error "Public IP address '$($ipConfig.PublicIpAddress.Id)' is not set to static allocation! Script will exit to ensure that the VM's public IP addresses are not lost."
                    }
                    Add-LogEntry "Disassociating public IP address '$($ipConfig.PublicIpAddress.Id)' from VM '$($VM.Name)', NIC '$($nic.Name)'..."
                    Set-AzNetworkInterfaceIpConfig -NetworkInterface $nic -Name $ipConfig.Name -PublicIpAddress $null | Out-Null
                }

                Add-LogEntry "Applying updates to the NIC '$($nic.Name)'..."
                If (!$WhatIf) {
                    $nic | Set-AzNetworkInterface | Out-Null
                }
                Else {
                    Add-LogEntry "WhatIf: Updating NIC with: `$nic | Set-AzNetworkInterface"
                }
            }

            # upgrade all public IP addresses
            Add-LogEntry "Upgrading all public IP addresses to Standard SKU..."
            ForEach ($publicIP in $publicIPIPConfigAssociations.publicIP) {
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
                Foreach ($nic in $vmNICs) {
                    ForEach ($assocation in ($publicIPIPConfigAssociations | Where-Object { $_.ipconfig.Id -like "$($nic.Id)/*" })) {
                        Add-LogEntry "Reassociating public IP address '$($assocation.publicIPId)' to VM '$($VM.Name)', NIC '$($nic.Name)'..."
                        Set-AzNetworkInterfaceIpConfig -NetworkInterface $nic -Name $assocation.ipConfig.Name -PublicIpAddress $assocation.publicIP | Out-Null
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

        Add-LogEntry "Upgrade of VM '$($VM.Name)' complete.'"
    }

    END {
        Add-LogEntry "####### Upgrade process complete. #######"
    }
}