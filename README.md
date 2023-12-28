# Azure Load Balancer Upgrade and Migration Modules

This repository hosts multiple modules related to migration and upgrade of Azure Load Balancers and Public IPs.

## Upgrade a basic load balancer with PowerShell Official documentation

Reference to the official documentation: [Upgrade a basic load balancer with PowerShell](https://learn.microsoft.com/en-us/azure/load-balancer/upgrade-basic-standard-with-powershell)

## Azure Basic Load Balancer Upgrade

This module migrates a Basic SKU Load Balancer to a Standard SKU Load Balancer. See [Azure Basic Load Balancer Upgrade](AzureBasicLoadBalancerUpgrade/README.md)

## Azure Load Balancer NAT Pool Migration

This module migrates NAT Pools to NAT Rules on a Standard SKU Load Balancer. See [Azure Load Balancer NAT Pool Migration](AzureLoadBalancerNATPoolMigration/README.md)

## Azure VM Public IP Address Upgrade

This module upgrades Public IPs attached to the specified VM from Basic SKU to Standard SKU. See [Azure VM Public IP Upgrade](AzureVMBasicPublicIPUpgrade/README.md)

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
