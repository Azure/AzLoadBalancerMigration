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
      'fd00:db8:deca::/48'
    ]
    name: 'vnet-01'
    subnets: [
      {
        name: 'subnet-v4'
        addressPrefix: '10.0.0.0/24'

      }
      {
        name: 'subnet-v6'
        addressPrefix: 'fd00:db8:deca:deed::/64'

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
            name: 'ipconfigv4'
            subnetResourceId: virtualNetworks.outputs.subnetResourceIds[0]
            loadBalancerBackendAddressPools: []
            pipconfiguration: {
              publicIpNameSuffix: '-pipv4-01'
            }
            publicIPAllocationMethod: 'Dynamic'
            skuName: 'Basic'

          }
          {
            name: 'ipconfigv6'
            subnetResourceId: virtualNetworks.outputs.subnetResourceIds[1]
            loadBalancerBackendAddressPools: []
            pipconfiguration: {
              publicIpNameSuffix: '-pipv6-01'
            }
            publicIPAllocationMethod: 'Dynamic'
            publicIPAddressVersion: 'IPv6'
            privateIPAddressVersion: 'IPv6'
            skuName: 'Basic'

          }

        ]
        nicSuffix: 'nic'
        enableAcceleratedNetworking: false
        networkSecurityGroupResourceId: nsg.outputs.resourceId
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
