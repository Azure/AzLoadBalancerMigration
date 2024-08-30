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

module nsg '../modules/Microsoft.Network/networkSecurityGroups/deploy.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'nsg-01'
  params: {
    name: 'nsg-01'
    location: location
  }
  dependsOn: [ rg ]
}

module availabilitySets '../modules/Microsoft.Compute/availabilitySets/deploy.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'avset-01'
  params: {
    name: 'avset-01'
    location: location
  }
  dependsOn: [
    rg
  ]
}

module vm1 '../modules/Microsoft.Compute/virtualMachines_custom/deploy.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'vm-01'
  params: {
    adminUsername: 'admin-vm'
    name: 'vm-01'
    adminPassword: '${uniqueString(randomGuid)}rpP@340'
    availabilitySetResourceId: availabilitySets.outputs.resourceId
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
            //networkSecurityGroup: nsg.outputs.resourceId
          }

        ]
        nicSuffix: 'nic'
        enableAcceleratedNetworking: false
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

module vm2 '../modules/Microsoft.Compute/virtualMachines_custom/deploy.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'vm-02'
  params: {
    name: 'vm-02'
    adminUsername: 'admin-vm'
    adminPassword: '${uniqueString(randomGuid)}rpP@340'
    availabilitySetResourceId: availabilitySets.outputs.resourceId
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
            networkSecurityGroup: nsg.outputs.resourceId
          }
        ]
        nicSuffix: 'nic'
        enableAcceleratedNetworking: false
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
