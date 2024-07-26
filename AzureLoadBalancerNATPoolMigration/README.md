# Migrate from Inbound NAT Pools to NAT Rules

Azure Load Balancer NAT Pools are the legacy approach for automatically assigning Load Balancer front end ports to each instance in a Virtual Machine Scale Set. NAT Rules on Standard SKU Load Balancers have replaced this functionality with an approach that is both easier to manage and faster to configure. 

## Why Migrate to NAT Rules?

NAT Rules provide the same functionality as NAT Pools, but have the following advantages:
* NAT Rules can be managed using the Portal
* NAT Rules can leverage Backend Pools, simplifying configuration
* NAT Rules configuration changes apply more quickly than NAT Pools
* NAT Pools cannot be used in conjunction with user-configured NAT Rules

## Migration Process

The migration process will create a new backend pool for each migrated NAT Pool by default. Alternatively, specify `-reuseBackendPools` to instead reuse existing backend pools if the is a backend pool with the same membership as the NAT Pool (if not, a new one will be created). Backend pools and NAT Rule associations can be updated post migration to match your preference.

> [!IMPORTANT]
> The migration process removes the Virtual Machine Scale Set(s) from the NAT Pools before associating the Virtual Machine Scale Set(s) with the new NAT Rules. This requires an update to the Virtual Machine Scale Set(s) model, which may cause a brief downtime while instances are upgraded with the model.

> [!NOTE]
> Frontend port mapping to Virtual Machine Scale Set instances may change with the move to NAT Rules, especially in situations where a single NAT Pool has multiple associated Virtual Machine Scale Sets. The new port assignment will align sequentially to instance ID numbers; when there are multiple Virtual Machine Scale Sets, ports will be assigned to all instances in one scale set, then the next, continuing. 

> [!NOTE]
> Service Fabric Clusters take significantly longer to update the Virtual Machine Scale Set model (up to an hour). 

### Prerequisites 

* In order to migrate a Load Balancer's NAT Pools to NAT Rules, the Load Balancer SKU must be 'Standard'. To automate this upgrade process, see the steps provided in [Upgrade a basic load balancer used with Virtual Machine Scale Sets](upgrade-basic-standard-virtual-machine-scale-sets.md).
* Virtual Machine Scale Sets associated with the target Load Balancer must use either a 'Manual' or 'Automatic' upgrade policy--'Rolling' upgrade policy is not supported. For more information, see [Virtual Machine Scale Sets Upgrade Policies](../virtual-machine-scale-sets/virtual-machine-scale-sets-upgrade-scale-set.md#how-to-bring-vms-up-to-date-with-the-latest-scale-set-model)
* Install the latest version of [PowerShell](/powershell/scripting/install/installing-powershell)
* Install the [Azure PowerShell modules](/powershell/azure/install-az-ps)

### Install the 'AzureLoadBalancerNATPoolMigration' module

Install the module from the [PowerShell Gallery](https://www.powershellgallery.com/packages/AzureLoadBalancerNATPoolMigration)

```azurepowershell
Install-Module -Name AzureLoadBalancerNATPoolMigration -Scope CurrentUser -Repository PSGallery -Force
```

### Use the module to upgrade NAT Pools to NAT Rules

1. Connect to Azure with `Connect-AzAccount`
1. Find the target Load Balancer for the NAT Rules upgrade and note its name and Resource Group name
1. Run the migration command

#### Example: specify the Load Balancer name and Resource Group name
   ```azurepowershell
   Start-AzNATPoolMigration -ResourceGroupName <loadBalancerResourceGroupName> -LoadBalancerName <LoadBalancerName>
   ```

#### Example: pass a Load Balancer from the pipeline
   ```azurepowershell
   Get-AzLoadBalancer -ResourceGroupName -ResourceGroupName <loadBalancerResourceGroupName> -Name <LoadBalancerName> | Start-AzNATPoolMigration
   ```

#### Example: reuse existing backend pools with membership matching NAT pools
   ```azurepowershell
   Start-AzNATPoolMigration -ResourceGroupName <loadBalancerResourceGroupName> -LoadBalancerName <LoadBalancerName> -reuseBackendPools
   ```

## Common Questions

### Will migration cause downtime to my NAT ports?

Yes, because we must first remove the NAT Pools before we can create the NAT Rules, there will be a brief time where there is no mapping of the front end port to a back end port.

> [!NOTE]
> Downtime for NAT'ed port on Service Fabric clusters will be significantly longer--up to an hour for a Silver cluster in testing. 

### Do I need to keep both the new Backend Pools created during the migration and my existing Backend Pools if the membership is the same?

No, following the migration, you can review the new backend pools. If the membership is the same between backend pools, you can replace the new backend pool in the NAT Rule with an existing backend pool, then remove the new backend pool. 

## Next steps

- Learn about [Managing Inbound NAT Rules](./manage-inbound-nat-rules.md)
- Learn about [Azure Load Balancer NAT Pools and NAT Rules](https://azure.microsoft.com/blog/manage-port-forwarding-for-backend-pool-with-azure-load-balancer/)

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