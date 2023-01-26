param location string
param resourceGroupName string

targetScope = 'subscription'

// Resource Group
module rg '../modules/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: resourceGroupName
  params: {
    name: resourceGroupName
    location: location
    managedBy: ''
  }
}

module kv '../modules/Microsoft.KeyVault/vaults/deploy.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'keyvault-deployment'
  params: {
    name: 'kv${uniqueString(subscription().id, resourceGroupName)}'
    location: location
    enableVaultForDeployment: true
    secrets: {
      secureList: [
        {
          name: 'adminUsername'
          value: 'admin-vmss'
        }
        {
          name: 'adminPassword'
          value: guid(subscription().id)
        }
      ]
    }
  }
  dependsOn: [
    rg
  ]
}
