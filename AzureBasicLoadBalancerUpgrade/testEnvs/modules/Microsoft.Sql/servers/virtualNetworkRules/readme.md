# Sql Servers VirtualNetworkRules `[Microsoft.Sql/servers/virtualNetworkRules]`

This module deploys a Sql Server Virtual Network Rule.

## Navigation

- [Resource Types](#Resource-Types)
- [Parameters](#Parameters)
- [Outputs](#Outputs)
- [Cross-referenced modules](#Cross-referenced-modules)

## Resource Types

| Resource Type | API Version |
| :-- | :-- |
| `Microsoft.Sql/servers/virtualNetworkRules` | [2022-02-01-preview](https://docs.microsoft.com/en-us/azure/templates/Microsoft.Sql/2022-02-01-preview/servers/virtualNetworkRules) |

## Parameters

**Required parameters**

| Parameter Name | Type | Description |
| :-- | :-- | :-- |
| `name` | string | The name of the Server Virtual Network Rule. |
| `virtualNetworkSubnetId` | string | The resource ID of the virtual network subnet. |

**Conditional parameters**

| Parameter Name | Type | Description |
| :-- | :-- | :-- |
| `serverName` | string | The name of the parent SQL Server. Required if the template is used in a standalone deployment. |

**Optional parameters**

| Parameter Name | Type | Default Value | Description |
| :-- | :-- | :-- | :-- |
| `enableDefaultTelemetry` | bool | `True` | Enable telemetry via a Globally Unique Identifier (GUID). |
| `ignoreMissingVnetServiceEndpoint` | bool | `False` | Allow creating a firewall rule before the virtual network has vnet service endpoint enabled. |


## Outputs

| Output Name | Type | Description |
| :-- | :-- | :-- |
| `name` | string | The name of the deployed virtual network rule. |
| `resourceGroupName` | string | The resource group of the deployed virtual network rule. |
| `resourceId` | string | The resource ID of the deployed virtual network rule. |

## Cross-referenced modules

_None_
