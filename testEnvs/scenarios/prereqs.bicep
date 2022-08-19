targetScope = 'subscription'
var location = 'eastus'
var resourceGroupName = 'rg-vmsstestingconfig'

// Resource Group
module rg '../modules/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: resourceGroupName
  params: {
    name: resourceGroupName
    location: location
  }
}

module kv '../modules/Microsoft.KeyVault/vaults/deploy.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'kvvmss${uniqueString(subscription().id)}'
  params: {
    name: 'kvvmss${uniqueString(subscription().id)}'
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
