# Policy Exemptions `[Microsoft.Authorization/policyExemptions]`

With this module you can create policy exemptions across the management group, subscription or resource group scope.

## Navigation

- [Resource types](#Resource-types)
- [Parameters](#Parameters)
- [Module Usage Guidance](#Module-Usage-Guidance)
- [Outputs](#Outputs)
- [Considerations](#Considerations)
- [Cross-referenced modules](#Cross-referenced-modules)
- [Deployment examples](#Deployment-examples)

## Resource types

| Resource Type | API Version |
| :-- | :-- |
| `Microsoft.Authorization/policyExemptions` | [2020-07-01-preview](https://docs.microsoft.com/en-us/azure/templates/Microsoft.Authorization/2020-07-01-preview/policyExemptions) |

## Parameters

**Required parameters**
| Parameter Name | Type | Description |
| :-- | :-- | :-- |
| `name` | string | Specifies the name of the policy exemption. Maximum length is 64 characters for management group, subscription and resource group scopes. |
| `policyAssignmentId` | string | The resource ID of the policy assignment that is being exempted. |

**Optional parameters**
| Parameter Name | Type | Default Value | Allowed Values | Description |
| :-- | :-- | :-- | :-- | :-- |
| `description` | string | `''` |  | The description of the policy exemption. |
| `displayName` | string | `''` |  | The display name of the policy exemption. Maximum length is 128 characters. |
| `enableDefaultTelemetry` | bool | `True` |  | Enable telemetry via the Customer Usage Attribution ID (GUID). |
| `exemptionCategory` | string | `'Mitigated'` | `[Mitigated, Waiver]` | The policy exemption category. Possible values are Waiver and Mitigated. Default is Mitigated. |
| `expiresOn` | string | `''` |  | The expiration date and time (in UTC ISO 8601 format yyyy-MM-ddTHH:mm:ssZ) of the policy exemption. e.g. 2021-10-02T03:57:00.000Z. |
| `location` | string | `[deployment().location]` |  | Location deployment metadata. |
| `managementGroupId` | string | `[managementGroup().name]` |  | The group ID of the management group to be exempted from the policy assignment. If not provided, will use the current scope for deployment. |
| `metadata` | object | `{object}` |  | The policy exemption metadata. Metadata is an open ended object and is typically a collection of key-value pairs. |
| `policyDefinitionReferenceIds` | array | `[]` |  | The policy definition reference ID list when the associated policy assignment is an assignment of a policy set definition. |
| `resourceGroupName` | string | `''` |  | The name of the resource group to be exempted from the policy assignment. Must also use the subscription ID parameter. |
| `subscriptionId` | string | `''` |  | The subscription ID of the subscription to be exempted from the policy assignment. Cannot use with management group ID parameter. |


### Parameter Usage: `managementGroupId`

To deploy resource to a Management Group, provide the `managementGroupId` as an input parameter to the module.


<details>

<summary>Parameter JSON format</summary>

```json
"managementGroupId": {
    "value": "contoso-group"
}
```

</details>


<details>

<summary>Bicep format</summary>

```bicep
managementGroupId: 'contoso-group'
```

</details>
<p>

> `managementGroupId` is an optional parameter. If not provided, the deployment will use the management group defined in the current deployment scope (i.e. `managementGroup().name`).

### Parameter Usage: `subscriptionId`

To deploy resource to an Azure Subscription, provide the `subscriptionId` as an input parameter to the module. **Example**:

<details>

<summary>Parameter JSON format</summary>

```json
"subscriptionId": {
    "value": "12345678-b049-471c-95af-123456789012"
}
```

</details>

<details>

<summary>Bicep format</summary>

```bicep
subscriptionId: '12345678-b049-471c-95af-123456789012'
```

</details>
<p>

### Parameter Usage: `resourceGroupName`

To deploy resource to a Resource Group, provide the `subscriptionId` and `resourceGroupName` as an input parameter to the module. **Example**:

```json
"subscriptionId": {
    "value": "12345678-b049-471c-95af-123456789012"
},
"resourceGroupName": {
    "value": "target-resourceGroup"
}
```

> The `subscriptionId` is used to enable deployment to a Resource Group Scope, allowing the use of the `resourceGroup()` function from a Management Group Scope. [Additional Details](https://github.com/Azure/bicep/pull/1420).

## Module Usage Guidance

In general, most of the resources under the `Microsoft.Authorization` namespace allows deploying resources at multiple scopes (management groups, subscriptions, resource groups). The `deploy.bicep` root module is simply an orchestrator module that targets sub-modules for different scopes as seen in the parameter usage section. All sub-modules for this namespace have folders that represent the target scope. For example, if the orchestrator module in the [root](deploy.bicep) needs to target 'subscription' level scopes. It will look at the relative path ['/subscription/deploy.bicep'](./subscription/deploy.bicep) and use this sub-module for the actual deployment, while still passing the same parameters from the root module.

The above method is useful when you want to use a single point to interact with the module but rely on parameter combinations to achieve the target scope. But what if you want to incorporate this module in other modules with lower scopes? This would force you to deploy the module in scope `managementGroup` regardless and further require you to provide its ID with it. If you do not set the scope to management group, this would be the error that you can expect to face:

```bicep
Error BCP134: Scope "subscription" is not valid for this module. Permitted scopes: "managementGroup"
```

The solution is to have the option of directly targeting the sub-module that achieves the required scope. For example, if you have your own Bicep file wanting to create resources at the subscription level, and also use some of the modules from the `Microsoft.Authorization` namespace, then you can directly use the sub-module ['/subscription/deploy.bicep'](./subscription/deploy.bicep) as a path within your repository, or reference that same published module from the bicep registry. CARML also published the sub-modules so you would be able to reference it like the following:

**Bicep Registry Reference**
```bicep
module policyexemption 'br:bicepregistry.azurecr.io/bicep/modules/microsoft.authorization.policyexemptions.subscription:version' = {}
```
**Local Path Reference**
```bicep
module policyexemption 'yourpath/modules/Microsoft.Authorization.policyExemptions/subscription/deploy.bicep' = {}
```

## Outputs

| Output Name | Type | Description |
| :-- | :-- | :-- |
| `name` | string | Policy Exemption Name. |
| `resourceId` | string | Policy Exemption resource ID. |
| `scope` | string | Policy Exemption Scope. |

## Considerations

- Policy Exemptions have a dependency on Policy Assignments being applied before creating an exemption. You can use the Policy Assignment [Module](../policyAssignments/deploy.bicep) to deploy a Policy Assignment and then create the exemption for it on the required scope.

## Cross-referenced modules

_None_

## Deployment examples

The following module usage examples are retrieved from the content of the files hosted in the module's `.test` folder.
   >**Note**: The name of each example is based on the name of the file from which it is taken.
   >**Note**: Each example lists all the required parameters first, followed by the rest - each in alphabetical order.

<h3>Example 1: Mg Min</h3>

<details>

<summary>via Bicep module</summary>

```bicep
module policyExemptions './Microsoft.Authorization/policyExemptions/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-policyExemptions'
  params: {
    // Required parameters
    name: '<<namePrefix>>-min-mg-polexem'
    policyAssignmentId: '/providers/Microsoft.Management/managementGroups/<<managementGroupId>>/providers/Microsoft.Authorization/policyAssignments/adp-<<namePrefix>>-mg-pass-loc-rg'
  }
}
```

</details>
<p>

<details>

<summary>via JSON Parameter file</summary>

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    // Required parameters
    "name": {
      "value": "<<namePrefix>>-min-mg-polexem"
    },
    "policyAssignmentId": {
      "value": "/providers/Microsoft.Management/managementGroups/<<managementGroupId>>/providers/Microsoft.Authorization/policyAssignments/adp-<<namePrefix>>-mg-pass-loc-rg"
    }
  }
}
```

</details>
<p>

<h3>Example 2: Mg</h3>

<details>

<summary>via Bicep module</summary>

```bicep
module policyExemptions './Microsoft.Authorization/policyExemptions/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-policyExemptions'
  params: {
    // Required parameters
    name: '<<namePrefix>>-mg-polexem'
    policyAssignmentId: '/providers/Microsoft.Management/managementGroups/<<managementGroupId>>/providers/Microsoft.Authorization/policyAssignments/adp-<<namePrefix>>-mg-pass-loc-rg'
    // Non-required parameters
    displayName: '[Display Name] policy exempt (management group scope)'
    exemptionCategory: 'Waiver'
    expiresOn: '2025-10-02T03:57:00Z'
    managementGroupId: '<<managementGroupId>>'
    metadata: {
      category: 'Security'
    }
  }
}
```

</details>
<p>

<details>

<summary>via JSON Parameter file</summary>

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    // Required parameters
    "name": {
      "value": "<<namePrefix>>-mg-polexem"
    },
    "policyAssignmentId": {
      "value": "/providers/Microsoft.Management/managementGroups/<<managementGroupId>>/providers/Microsoft.Authorization/policyAssignments/adp-<<namePrefix>>-mg-pass-loc-rg"
    },
    // Non-required parameters
    "displayName": {
      "value": "[Display Name] policy exempt (management group scope)"
    },
    "exemptionCategory": {
      "value": "Waiver"
    },
    "expiresOn": {
      "value": "2025-10-02T03:57:00Z"
    },
    "managementGroupId": {
      "value": "<<managementGroupId>>"
    },
    "metadata": {
      "value": {
        "category": "Security"
      }
    }
  }
}
```

</details>
<p>

<h3>Example 3: Rg Min</h3>

<details>

<summary>via Bicep module</summary>

```bicep
module policyExemptions './Microsoft.Authorization/policyExemptions/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-policyExemptions'
  params: {
    // Required parameters
    name: '<<namePrefix>>-min-rg-polexem'
    policyAssignmentId: '/subscriptions/<<subscriptionId>>/providers/Microsoft.Authorization/policyAssignments/adp-<<namePrefix>>-sb-pass-loc-rg'
    // Non-required parameters
    resourceGroupName: '<<resourceGroupName>>'
    subscriptionId: '<<subscriptionId>>'
  }
}
```

</details>
<p>

<details>

<summary>via JSON Parameter file</summary>

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    // Required parameters
    "name": {
      "value": "<<namePrefix>>-min-rg-polexem"
    },
    "policyAssignmentId": {
      "value": "/subscriptions/<<subscriptionId>>/providers/Microsoft.Authorization/policyAssignments/adp-<<namePrefix>>-sb-pass-loc-rg"
    },
    // Non-required parameters
    "resourceGroupName": {
      "value": "<<resourceGroupName>>"
    },
    "subscriptionId": {
      "value": "<<subscriptionId>>"
    }
  }
}
```

</details>
<p>

<h3>Example 4: Rg</h3>

<details>

<summary>via Bicep module</summary>

```bicep
module policyExemptions './Microsoft.Authorization/policyExemptions/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-policyExemptions'
  params: {
    // Required parameters
    name: '<<namePrefix>>-rg-polexem'
    policyAssignmentId: '/subscriptions/<<subscriptionId>>/providers/Microsoft.Authorization/policyAssignments/adp-<<namePrefix>>-sb-pass-loc-rg'
    // Non-required parameters
    displayName: '[Display Name] policy exempt (resource group scope)'
    exemptionCategory: 'Waiver'
    expiresOn: '2025-10-02T03:57:00Z'
    metadata: {
      category: 'Security'
    }
    resourceGroupName: '<<resourceGroupName>>'
    subscriptionId: '<<subscriptionId>>'
  }
}
```

</details>
<p>

<details>

<summary>via JSON Parameter file</summary>

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    // Required parameters
    "name": {
      "value": "<<namePrefix>>-rg-polexem"
    },
    "policyAssignmentId": {
      "value": "/subscriptions/<<subscriptionId>>/providers/Microsoft.Authorization/policyAssignments/adp-<<namePrefix>>-sb-pass-loc-rg"
    },
    // Non-required parameters
    "displayName": {
      "value": "[Display Name] policy exempt (resource group scope)"
    },
    "exemptionCategory": {
      "value": "Waiver"
    },
    "expiresOn": {
      "value": "2025-10-02T03:57:00Z"
    },
    "metadata": {
      "value": {
        "category": "Security"
      }
    },
    "resourceGroupName": {
      "value": "<<resourceGroupName>>"
    },
    "subscriptionId": {
      "value": "<<subscriptionId>>"
    }
  }
}
```

</details>
<p>

<h3>Example 5: Sub Min</h3>

<details>

<summary>via Bicep module</summary>

```bicep
module policyExemptions './Microsoft.Authorization/policyExemptions/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-policyExemptions'
  params: {
    // Required parameters
    name: '<<namePrefix>>-min-sub-polexem'
    policyAssignmentId: '/subscriptions/<<subscriptionId>>/providers/Microsoft.Authorization/policyAssignments/adp-<<namePrefix>>-sb-pass-loc-rg'
    // Non-required parameters
    subscriptionId: '<<subscriptionId>>'
  }
}
```

</details>
<p>

<details>

<summary>via JSON Parameter file</summary>

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    // Required parameters
    "name": {
      "value": "<<namePrefix>>-min-sub-polexem"
    },
    "policyAssignmentId": {
      "value": "/subscriptions/<<subscriptionId>>/providers/Microsoft.Authorization/policyAssignments/adp-<<namePrefix>>-sb-pass-loc-rg"
    },
    // Non-required parameters
    "subscriptionId": {
      "value": "<<subscriptionId>>"
    }
  }
}
```

</details>
<p>

<h3>Example 6: Sub</h3>

<details>

<summary>via Bicep module</summary>

```bicep
module policyExemptions './Microsoft.Authorization/policyExemptions/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-policyExemptions'
  params: {
    // Required parameters
    name: '<<namePrefix>>-sub-polexem'
    policyAssignmentId: '/subscriptions/<<subscriptionId>>/providers/Microsoft.Authorization/policyAssignments/adp-<<namePrefix>>-sb-pass-loc-rg'
    // Non-required parameters
    displayName: '[Display Name] policy exempt (subscription scope)'
    exemptionCategory: 'Waiver'
    expiresOn: '2025-10-02T03:57:00Z'
    metadata: {
      category: 'Security'
    }
    subscriptionId: '<<subscriptionId>>'
  }
}
```

</details>
<p>

<details>

<summary>via JSON Parameter file</summary>

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    // Required parameters
    "name": {
      "value": "<<namePrefix>>-sub-polexem"
    },
    "policyAssignmentId": {
      "value": "/subscriptions/<<subscriptionId>>/providers/Microsoft.Authorization/policyAssignments/adp-<<namePrefix>>-sb-pass-loc-rg"
    },
    // Non-required parameters
    "displayName": {
      "value": "[Display Name] policy exempt (subscription scope)"
    },
    "exemptionCategory": {
      "value": "Waiver"
    },
    "expiresOn": {
      "value": "2025-10-02T03:57:00Z"
    },
    "metadata": {
      "value": {
        "category": "Security"
      }
    },
    "subscriptionId": {
      "value": "<<subscriptionId>>"
    }
  }
}
```

</details>
<p>
