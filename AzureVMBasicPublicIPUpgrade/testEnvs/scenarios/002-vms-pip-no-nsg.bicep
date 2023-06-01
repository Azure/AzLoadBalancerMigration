targetScope = 'subscription'
param location string
param resourceGroupName string
param randomGuid string = newGuid()

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
  name: '${uniqueString(deployment().name)}-virtualNetworks'
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

module storageAccounts '../modules/Microsoft.Storage/storageAccounts/deploy.bicep' = {
  name: 'bootdiag-storage-01'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'bootdiag${uniqueString(deployment().name)}'
    location: location
    storageAccountSku: 'Standard_LRS'
    storageAccountKind: 'StorageV2'
    supportsHttpsTrafficOnly: true
  }
  dependsOn: [
    rg
  ]
}

module vm '../modules/Microsoft.Compute/virtualMachines_custom/deploy.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'vm-01'
  params: {
    adminUsername: 'admin-vm'
    adminPassword: '${uniqueString(randomGuid)}rpP@340'
    location: location
    imageReference: {
      offer: 'UbuntuServer'
      publisher: 'Canonical'
      sku: '18.04-LTS'
      version: 'latest'
    }
    nicConfigurations: [
      {
        location: location
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: virtualNetworks.outputs.subnetResourceIds[0]
            loadBalancerBackendAddressPools: []
            pipConfiguration: {
              publicIpNameSuffix: '-pip-01'
            }
            skuName: 'Basic'
          }
          {
            name: 'ipconfig2'
            primary: false
            subnetResourceId: virtualNetworks.outputs.subnetResourceIds[0]
            loadBalancerBackendAddressPools: []
            pipConfiguration: {
              publicIpNameSuffix: '-pip-02'
            }
            skuName: 'Basic'
            publicIPAllocationMethod: 'Dynamic'
          }
        ]
        nicSuffix: 'nic'
        enableAcceleratedNetworking: false
      }
      {
        nicSuffix: 'nic2'
        enableAcceleratedNetworking: false
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: virtualNetworks.outputs.subnetResourceIds[0]
            pipConfiguration: {
              publicIpNameSuffix: '-pip-03'
            }
            skuName: 'Basic'
            publicIPAllocationMethod: 'Dynamic'
          }
        ]
      }
    ]
    osDisk: {
      createOption: 'fromImage'
      diskSizeGB: '128'
      managedDisk: {
        storageAccountType: 'Standard_LRS'
      }
    }
    osType: 'Linux'
    vmSize: 'Standard_DS1_v2'
  }
}
