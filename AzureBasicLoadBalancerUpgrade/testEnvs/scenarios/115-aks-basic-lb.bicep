targetScope = 'subscription'
param location string
param resourceGroupName string
param vmSize string = 'Standard_D2_v2'

// Resource Group
module rg '../modules/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: '${resourceGroupName}-${location}'
  params: {
    name: resourceGroupName
    location: location
  }
}

// vnet
module virtualNetworks '../modules/Microsoft.Network/virtualNetworks/deploy.bicep' = {
  name: 'virtualNetworks-module'
  scope: resourceGroup(resourceGroupName)
  params: {
    // Required parameters
    location: location
    addressPrefixes: [
      '10.0.0.0/16'
    ]
    name: 'vnet-01'
    subnets: [
      {
        name: 'subnet-01'
        addressPrefix: '10.0.1.0/24'
      }
    ]
  }
  dependsOn: [
    rg
  ]
}

module aks '../modules/aks/aks.bicep' = {
  name: 'aks-module'
  scope: resourceGroup(resourceGroupName)
  params: {
    k8sVersion: '1.29'
    location: location
    subnetId: virtualNetworks.outputs.subnetResourceIds[0]
    vmSize: vmSize
    loadBalancerType: 'basic'
  }
  dependsOn: [
    virtualNetworks
  ]
}
