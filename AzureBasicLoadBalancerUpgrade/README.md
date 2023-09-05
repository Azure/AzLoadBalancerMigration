# Upgrade a basic load balancer used with Virtual Machine Scale Sets
[Azure Standard Load Balancer](load-balancer-overview.md) offers a rich set of functionality and high availability through zone redundancy. To learn more about Load Balancer SKU, see [comparison table](https://learn.microsoft.com/azure/load-balancer/skus).

This article introduces a PowerShell module that creates a Standard Load Balancer with the same configuration as the Basic Load Balancer along with the associated  Virtual Machine Scale Set.

## Upgrade Overview

An Azure PowerShell module is available to upgrade from Basic load balancer to a Standard load balancer along with moving the associated Virtual Machine Scale set (VMSS). The PowerShell module performs the following functions:

- Verifies that the provided Basic load balancer scenario is supported for upgrade.
- Backs up the Basic load balancer and Virtual Machine Scale set (VMSS) configuration, enabling retry on failure or if errors are encountered.
- For public load balancers, updates the front end public IP address(es) to Standard SKU and static assignment as required.
- Upgrade the Basic load balancer configuration to a new Standard load balancer, ensuring configuration and feature parity.
- Upgrade VMSS backend pool members from the Basic load balancer to the standard load balancer.
- Creates and associates a NSG with the VMSS to ensure load balanced traffic reaches backend pool members, following Standard load balancer's move to a default-deny network policy.
- Logs the upgrade operation for easy audit and failure recovery.

> **Warning**
> Migrating _internal_ Basic Load Balancers where the backend VMs or VMSS instances do not have Public IP Addresses assigned requires additional action post-migration to enable backend pool members to connect to the internet. The recommended approach is to create a NAT Gateway and assign it to the backend pool members' subnet (see: [**Integrate NAT Gateway with Internal Load Balancer**](https://learn.microsoft.com/azure/virtual-network/nat-gateway/tutorial-nat-gateway-load-balancer-internal-portal)). Alternatively, Public IP Addresses can be allocated to each VMSS instance by adding a Public IP Configuration to the Network Profile (see: [**VMSS Public IPv4 Address Per Virtual Machine**](https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-networking.md)). 

> **Warning**
> If the Virtual Machine Scale Set in the Load Balancer backend pool has Public IP Addresses in its network configuration, the Public IP Addresses will change during migration (the Public IPs must be removed prior to the migration, then added back post migration with a Standard SKU configuration)

### Unsupported Scenarios

- Basic load balancers with a VMSS backend pool member which is also a member of a backend pool on a different load balancer
- Basic load balancers with backend pool members which are not a VMSS
- Basic load balancers with only empty backend pools
- Basic load balancers with IPV6 frontend IP configurations
- Basic load balancers with a VMSS backend pool member configured with 'Flexible' orchestration mode
- Basic load balancers with a VMSS backend pool member where one or more VMSS instances have ProtectFromScaleSetActions Instance Protection policies enabled
- Migrating a Basic load balancer to an existing Standard load balancer

### Prerequisites

- Install the latest version of [PowerShell Desktop or Core ](https://learn.microsoft.com/powershell/scripting/windows-powershell/install/installing-windows-powershell)
- Determine whether you have the latest Az module installed (8.2.0)
  - Install the latest Az PowerShell module](https://learn.microsoft.com/powershell/azure/install-az-ps)

## Install the 'AzureBasicLoadBalancerUpgrade' module

Install the module from [PowerShell gallery](https://www.powershellgallery.com/packages/AzureBasicLoadBalancerUpgrade)

```powershell
PS C:\> Install-Module -Name AzureBasicLoadBalancerUpgrade -Scope CurrentUser -Repository PSGallery -Force
```

## Use the module

1. Use `Connect-AzAccount` to connect to the required Azure AD tenant and Azure subscription

    ```powershell
    PS C:\> Connect-AzAccount -Tenant <TenantId> -Subscription <SubscriptionId>
    ```

2. Find the Load Balancer you wish to upgrade. Record its name and resource group name.

3. Examine the module parameters:
    - *BasicLoadBalancerName [string] Required* - This parameter is the name of the existing Basic load balancer you would like to upgrade
    - *ResourceGroupName [string] Required* - This parameter is the name of the resource group containing the Basic load balancer
    - *RecoveryBackupPath [string] Optional* - This parameter allows you to specify an alternative path in which to store the Basic load balancer ARM template backup file (defaults to the current working directory)
    - *FailedMigrationRetryFilePathLB [string] Optional* - This parameter allows you to specify a path to a Basic load balancer backup state file when retrying a failed upgrade (defaults to current working directory)
    - *FailedMigrationRetryFilePathVMSS [string] Optional* - This parameter allows you to specify a path to a Virtual Machine Scale set (VMSS) backup state file when retrying a failed upgrade (defaults to current working directory)

4. Run the Upgrade command.

### Example: upgrade a basic load balancer to a standard load balancer with the same name, providing the basic load balancer name and resource group

```powershell
PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName <load balancer resource group name> -BasicLoadBalancerName <existing basic load balancer name>
```

### Example: upgrade a basic load balancer to a standard load balancer with the same name, providing the basic load object through the pipeline

```powershell
PS C:\> Get-AzLoadBalancer -Name <basic load balancer name> -ResourceGroup <Basic load balancer resource group name> | Start-AzBasicLoadBalancerUpgrade
```

### Example: upgrade a basic load balancer to a standard load balancer with the specified name, displaying logged output on screen

```powershell
PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName <load balancer resource group name> -BasicLoadBalancerName <existing basic load balancer name> -StandardLoadBalancerName <new standard load balancer name> -FollowLog
```

### Example: upgrade a basic load balancer to a standard load balancer with the specified name and store the basic load balancer backup file at the specified path

```powershell
PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName <load balancer resource group name> -BasicLoadBalancerName <existing basic load balancer name> -StandardLoadBalancerName <new standard load balancer name> -RecoveryBackupPath C:\BasicLBRecovery
```

### Example: retry a failed VMSS backend scenario upgrade (due to error or script termination) by providing the Basic load balancer and VMSS backup state file

```powerhsell
PS C:\> Start-AzBasicLoadBalancerUpgrade -FailedMigrationRetryFilePathLB C:\RecoveryBackups\State_mybasiclb_rg-basiclbrg_20220912T1740032148.json -FailedMigrationRetryFilePathVMSS C:\RecoveryBackups\VMSS_myVMSS_rg-basiclbrg_20220912T1740032148.json
```

### Example: retry a failed VM backend scenario upgrade (due to error or script termination) by providing the Basic load balancer

```powerhsell
PS C:\> Start-AzBasicLoadBalancerUpgrade -FailedMigrationRetryFilePathLB C:\RecoveryBackups\State_mybasiclb_rg-basiclbrg_20220912T1740032148.json
```

## Common Questions

### Will the module migrate my frontend IP address to the new Standard load balancer?

Yes, for both public and internal load balancers, the module ensures that front end IP addresses are maintained. For public IPs, the IP is converted to a static IP prior to migration (if necessary). For internal front ends, the module will attempt to reassign the same IP address freed up when the Basic load balancer was deleted; if the private IP is not available the script will fail. In this scenario, remove the virtual network connected device which has claimed the intended front end IP and rerun the module with the `-FailedMigrationRetryFilePathLB <BasicLoadBalancerbackupFilePath> -FailedMigrationRetryFilePathVMSS <VMSSBackupFile>` parameters specified.

### How long does the Upgrade take?

It usually takes a few minutes for the script to finish and it could take longer depending on the complexity of your load balancer configuration, number of backend pool members, and instance count of associated Virtual Machine Scale Sets. Keep the downtime in mind and plan for failover if necessary.

### Does the script migrate my backend pool members from my basic load balancer to the newly created standard load balancer?

Yes. The Azure PowerShell script migrates the virtual machine scale set to the newly created public or private standard load balancer.

### Which load balancer components are migrated?

The script migrates the following from the Basic load balancer to the Standard load balancer:

**Public Load Balancer:**

- Public frontend IP configuration
  - Converts the public IP to a static IP, if dynamic
  - Updates the public IP SKU to Standard, if Basic
  - Upgrade all associated public IPs to the new Standard load balancer
- Health Probes:
  - All probes will be migrated to the new Standard load balancer
- Load balancing rules:
  - All load balancing rules will be migrated to the new Standard load balancer
- Inbound NAT Rules:
  - All NAT rules will be migrated to the new Standard load balancer
- Outbound Rules:
  - Basic load balancers do not support configured outbound rules. The script will create an outbound rule in the Standard load balancer to preserve the outbound behavior of the Basic load balancer. For more information about Outbound connectivity, see [Outbound-only load balancer configuration](https://learn.microsoft.com/azure/load-balancer/egress-only).
- Network Security Group
  - Basic load balancer doesn't required a Network Security Group to allow outbound connectivity. In case there is no Network Security Group associated with the VMSS, a new NSG will be created to preserve the same functionality. This new NSG will be associated to the VMSS backend pool member network interfaces and allow the same load balancing rules ports and protocols and preserve the outbound connectivity.
- Backend pools:
  - All backend pools will be migrated to the new Standard load balancer
  - All VMSS network interfaces and IP configurations will be migrated to the new Standard load balancer
  - In case of VMSS using Rolling Upgrade policy, the script will update the VMSS upgrade policy to "Manual" during the migration process and revert it back to "Rolling" after the migration is completed.

**Private Load Balancer:**

- Private frontend IP configuration
  - Converts the public IP to a static IP, if dynamic
  - Updates the public IP SKU to Standard, if Basic
- Health Probes:
  - All probes will be migrated to the new Standard load balancer
- Load balancing rules:
  - All load balancing rules will be migrated to the new Standard load balancer
- Inbound NAT Rules:
  - All NAT rules will be migrated to the new Standard load balancer
- Backend pools:
  - All backend pools will be migrated to the new Standard load balancer
  - All VMSS network interfaces and IP configurations will be migrated to the new Standard load balancer
  - In case of VMSS using Rolling Upgrade policy, the script will update the VMSS upgrade policy to "Manual" during the migration process and revert it back to "Rolling" after the migration is completed.

### What happens if my upgrade fails mid-migration?

The module is designed to accommodate failures, either due to unhandled errors or unexpected script termination. The failure design is a 'fail forward' approach, where instead of attempting to move back to the Basic load balancer, you should correct the issue causing the failure (see the error output or log file), and retry the migration again. For VMSS backends, specify the `-FailedMigrationRetryFilePathLB <BasicLoadBalancerbackupFilePath> -FailedMigrationRetryFilePathVMSS <VMSSBackupFile>` parameters; for VM backends, only specify the `-FailedMigrationRetryFilePathLB <BasicLoadBalancerbackupFilePath>` parameter`. For public load balancers, because the Public IP Address SKU has been updated to Standard, moving the same IP back to a Basic load balancer will not be possible. The basic failure recovery procedure is:

  1. Address the cause of the migration failure. Check the log file `Start-AzBasicLoadBalancerUpgrade.log` for details
  1. [Remove the new Standard load balancer](https://learn.microsoft.com/azure/load-balancer/update-load-balancer-with-vm-scale-set) (if created). Depending on which stage of the migration failed, you may have to remove the Standard load balancer reference from the VMSS network interfaces (IP configurations) and health probes in order to remove the Standard load balancer and try again.
  1. Locate the basic load balancer state backup file. This will either be in the directory where the script was executed, or at the path specified with the `-RecoveryBackupPath` parameter during the failed execution. The file will be named: `State_<basicLBName>_<basicLBRGName>_<timestamp>.json`
  1. Rerun the migration script, specifying the `-FailedMigrationRetryFilePathLB <BasicLoadBalancerbackupFilePath>` parameter and ` -FailedMigrationRetryFilePathVMSS <VMSSBackupFile>` for VMSS backends instead of -BasicLoadBalancerName or passing the Basic load balancer over the pipeline

## Next Steps

[Learn about the Azure Load Balancer](https://learn.microsoft.com/azure/load-balancer/load-balancer-overview)

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.