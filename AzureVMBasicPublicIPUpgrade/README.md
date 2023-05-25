# Azure VM Public IP Upgrade

This script upgrades the Public IP Addresses attached to VM to Standard SKU. In order to perform the upgrade, the Public IP Address
allocation method is set to static before being disassociated from the VM. Once disassociated, the Public IP SKU is upgraded to Standard,
then the IP is re-associated with the VM.

Because the Public IP allocation is set to 'Static' before detaching from the VM, the IP address will not change during the upgrade process,
even in the event of a script failure. For added peace of mind, the module double-checks that the Public IP allocation method is 'Static' 
prior to detaching the Public IP from the VM. 

The module logs all upgrade activity to a file named `PublicIPUpgrade.log`, created in the same location where the module was executed (by default). 

## Unsupported Scenarios

- **VMs with NICs associated to a Load Balancer**: because the Load Balancer and Public IP SKUs associated with a VM must match, it is not possible to upgrade the instance-level Public IP addresses associated with a VM when the VM's NICs are also associated with a Load Balancer, either though Backend Pool or NAT Pool membership. Use [Upgrade a basic load balancer used with Virtual Machine Scale Sets](../AzureBasicLoadBalancerUpgrade/README.md) to upgrade both the Load Balancer and Public IPs as the same time.
- **VMs without a Network Security Group**: VMs with IPs to be upgraded must have a Network Security Group (NSG) associated with either the subnet of each IP configuration with a Public IP, or with the NIC directly. This is because Standard SKU Public IPs are "secure by default", meaning that any traffic to the Public IP must be explicitly allowed at an NSG to reach the VM. Basic SKU Public IPs allow any traffic by default. Upgrading Public IP SKUs without an NSG will result in inbound internet traffic to the Public IP previously allowed with the Basic SKU being blocked post-migration. See: [Public IP SKUs](https://learn.microsoft.com/azure/virtual-network/ip-services/public-ip-addresses#sku)

## Install the 'AzureVMBasicPublicIPUpgrade' module

Install the module from [PowerShell gallery](https://www.powershellgallery.com/packages/AzureVMBasicPublicIPUpgrade)

```powershell
PS C:\> Install-Module -Name AzureVMBasicPublicIPUpgrade -Scope CurrentUser -Repository PSGallery -Force
```

## Use the module

1. Use `Connect-AzAccount` to connect to the required Azure AD tenant and Azure subscription

    ```powershell
    PS C:\> Connect-AzAccount -Tenant <TenantId> -Subscription <SubscriptionId>
    ```

1. Determine the VMs with Public IPs you want to upgrade. You can either specify VMs individually or pass multiple VMs to the module through the pipeline. 

1. Run the upgrade command, following the examples below.

**EXAMPLE: Upgrade a single VM, passing the VM name and resource group name as parameters.**

```powershell
    Start-VMPublicIPUpgrade -VMName 'myVM' -ResourceGroupName 'myRG'
```

**EXAMPLE: Evaluate upgrading a single VM, without making any changes.**

```powershell
    Start-VMPublicIPUpgrade -VMName 'myVM' -ResourceGroupName 'myRG' -WhatIf
```

**EXAMPLE: Upgrade All VMs, skipping those missing Network Security Groups.**

```powershell
        Get-AzVM -ResourceGroupName 'myRG' | Start-VMPublicIPUpgrade -skipVMMissingNSG
```

**EXAMPLE: Upgrade all VMs in a resource group, piping the VM objects to the script.**

```powershell
    Get-AzVM -ResourceGroupName 'myRG' | Start-VMPublicIPUpgrade
```

### Recovering from a Failed Migration

When a migration fails due to a transient issue, such as a network outage or client system crash, the migration can be re-run to configure the VM and Public IPs in the goal state. At execution, the script outputs a recovery log file which is used to ensure the VM is properly reconfigured. Review the log file `PublicIPUpgrade.log` created in the location where the script was executed.

To recover from a failed upgrade, pass the recovery log file path to the script with the `-recoverFromFile` parameter and identify the VM to recover with the `-VMName` and `-VMResourceGroup` or `-VMResourceID` parameters. 

**EXAMPLE: Recover from a failed migration, passing the name and resource group of the VM to recover, along with the recovery log file**

```powershell
    Start-VMPublicIPUpgrade -RecoverFromFile ./PublicIPUpgrade_Recovery_2020-01-01-00-00.csv -VMName myVM -VMResourceGroup -rg-myrg
```

## Frequently Asked Questions

### How long will the migration take and how long will my VM be inaccessible at its Public IP?

The time it takes to upgrade a VM's Public IPs will depend on the number of Public IPs and Network Interfaces associated with the VM. In testing, a VM with a single NIC and Public IP will take between 1 and 2 minutes to upgrade. Each NIC on the VM will add about another minute, and each Public IP adds a few seconds each.

### If something goes wrong with the upgrade can I roll back to a Basic SKU Public IP?

It is not possible to downgrade a Public IP address from Standard to Basic, so our recommendation is to fail-forward and address the issue with the Standard SKU IPs.

### Can I test a migration before executing? 

There is no way to evaluate upgrading a Public IP without completing the action. This script includes a `-whatif` parameter, which checks that your VM will support the upgrade and walks through the steps without taking action. 

### Does this script support Zonal Basic SKU Public IPs? 

Yes, the process of upgrading a Zonal Basic SKU Public IP to a Zonal Standard SKU Public IP is the same as a Regional Public IP.