# Upgrade from Basic load balancer to Standard load balancer for a Virtual Machine Scale set

### In this article
  Upgrade overview
  Download the modules
  Use the Module
  Common questions
  Next Steps

[Azure Standard Load Balancer](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-overview) offers a rich set of functionality and high availability through zone redundancy. To learn more about Azure Load Balancer SKUs, see [comparison table](https://docs.microsoft.com/en-us/azure/load-balancer/skus#skus).

The entire migration process for a load balancer with a Public or Private IP is handled by the PowerShell module. 

## Upgrade Overview

An Azure PowerShell module is available to migrate from a Basic to Standard load balancer. The PowerShell module exports a single function called 'Start-AzBasicLoadBalancerUpgrade' which performs the following procedures:

- Verifies that the Basic load balancer has a supported configuration
- Verifies tht the new Standard load balancer name is valid abd available.
- Determines whether the load balancer has a public or private IP address
- Backs up the current Basic load balancer configuration to an ARM template in order to provide the ability to recreate the Basic load balancer if an error occurs during migration.
- Removes the load balancer from the Virtual Machine Scale set
- Creates a new Standard load balancer 
- Upgrades a Basic Public IP to the Standard SKU (Public Load balancer only)
- Upgrades a dynamically assigned Public IP a Static IP address (Public Load balancer only)
- Migrates Frontend IP configurations
- Migrates Backend address pools
- Migrates NAT rules
- Migrates Inbound NAT pools
- Migrates Probes
- Migrates Load balancing rules
- Creates outbound rules for SNAT (Public Load balancer only)
- Creates NSG for outbound traffic (Public Load balancer only)

### Prerequisites
- Install the latest version of [PowerShell Desktop or Core ](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7.2)
- Determine whether you have the latest Az module installed (8.2.0)
  - Install the latest Az PowerShell module](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-8.3.0)

### Install the latest Az modules using Install-Module

```
PS C:\> Find-Module Az | Install-Module
```

## Download the 'VMSSLoadBalancerMigration' module

Download the module from [PowerShell gallery](https://www.powershellgallery.com/packages/AzureVMSSLoadBalancerUpgrade/0.1.0)

```
PS C:\> Find-Module VMSSLoadBalancerMigration | Install-Module
```

## Use the module

1. Use `Connect-AzAccount` to connect to the required Azure AD tenant and Azure subscription 

```
PS C:\> Connect-AzAccount -Tenant <TenantId> -Subscription <SubscriptionId> 
```

2. Find the Load Balancer you wish to migrate & record its name and containing resource group name

3. Examine the required parameters:
- *BasicLoadBalancerName [string] Required* - This parameter is the name of the existing Basic load balancer you would like to migrate
- *ResourceGroupName [string] Required* - This parameter is the name of the resource group containing the Basic load balancer
- *RecoveryBackupPath [string] Optional* - This parameter allows you to specify an alternative path in which to store the Basic load balancer ARM template backup file (defaults to the current working directory)
- *FailedMigrationRetryPath [string] Optional* - This parameter allows you to specify an alternative path in which to store the failed migration retry files (defaults to current working directory)

4. Run the upgrade command. 
- The new Standard load balancer will be created using the same name as the existing Basic Load Balancer, by default

### Example
```
PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName <load balancer resource group name> -BasicLoadBalancerName <existing basic load balancer name>
```

- Alternatively, use the PowerShell pipeline to pass the Basic load balancer object to the command

###  Example
```
PS C:\> Get-AzLoadBalancer -Name <basic load balancer name> -ResourceGroup <Basic load balancer resource group name> | Start-AzBasicLoadBalancerUpgrade
```

- Optionally, if you would like to specify a different name for the new Standard load balancer add the `-StandardLoadBalancerName` parameter

### Example
```
PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName <load balancer resource group name> -BasicLoadBalancerName <existing basic load balancer name> -StandardLoadBalancerName <new standard load balancer name>
```

- Optionally, if you would like to specify different paths for the `-RecoveryBackupPath` and `-FailedMigrationRetryFilePath` parameters

### Example
```
PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName <load balancer resource group name> -BasicLoadBalancerName <existing basic load balancer name> -StandardLoadBalancerName <new standard load balancer name> -RecoveryBackupPath C:\BasicLBRecovery -FailedMigrationRetryFilePath C:\FailedLBMigration
``` 

## Common Questions

### How long does the upgrade take?
It usually takes a few minutes for the script to finish and it could take longer depending on the complexity of your load balancer configuration. Keep the downtime in mind and plan for failover if necessary.

### Does the script switch over the traffic from my basic load balancer to the newly created standard load balancer?
Yes. The Azure PowerShell script upgrades the public IP address (if a public load balancer is discovered), copies the configuration from the basic to standard load balancer, and migrates the virtual machine scale set to the newly created public or private standard load balancer.

## Next Steps
[Learn about the Azure Load Balancer](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-overview)