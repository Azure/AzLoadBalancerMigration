targetScope = 'subscription'
param location string
param resourceGroupName string
param keyVaultName string
param keyVaultResourceGroupName string

// Resource Group
module rg '../modules/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: resourceGroupName
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

module publicIp01 '../modules/Microsoft.Network/publicIpAddresses/deploy.bicep' = {
  name: 'pip-01'
  params: {
    name: 'pip-01'
    location: location
    publicIPAddressVersion: 'IPv4'
    skuTier: 'Regional'
    skuName: 'Basic'
    publicIPAllocationMethod: 'Dynamic'
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

// basic lb
module loadbalancer '../modules/Microsoft.Network/loadBalancers_custom/deploy.bicep' = {
  name: 'lb-basic01'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'lb-basic-01'
    location: location
    frontendIPConfigurations: [
      {
        name: 'fe-01'
        publicIPAddressId: publicIp01.outputs.resourceId
      }
    ]
    backendAddressPools: [
      {
        name: 'be-01'
      }
    ]
    inboundNatRules: []
    loadBalancerSku: 'Basic'
    loadBalancingRules: [
      {
        backendAddressPoolName: 'be-01'
        backendPort: 80
        frontendIPConfigurationName: 'fe-01'
        frontendPort: 80
        idleTimeoutInMinutes: 4
        loadDistribution: 'Default'
        name: 'rule-01'
        probeName: 'probe-01'
        protocol: 'Tcp'
      }
    ]
    probes: [
      {
        intervalInSeconds: 5
        name: 'probe-01'
        numberOfProbes: 2
        port: '80'
        protocol: 'Tcp'
      }
    ]
  }
  dependsOn: [
    rg
  ]
}

resource kv1 'Microsoft.KeyVault/vaults@2019-09-01' existing = {
  name: keyVaultName
  scope: resourceGroup(keyVaultResourceGroupName)
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

module availabilitySet '../modules/Microsoft.Compute/availabilitySets/deploy.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'as-01'
  params: {
    location: location
    name: 'as-01'
  }
}

module vm '../modules/Microsoft.Compute/virtualMachines_custom/deploy.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'vm-01'
  params: {
    name: 'vm-01'
    adminUsername: 'admin-vm'
    adminPassword: '${uniqueString(randomGuid)}rpP@340'
    location: location
    availabilitySetResourceId: availabilitySet.outputs.resourceId
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
            loadBalancerBackendAddressPools: [
              {
                id: loadbalancer.outputs.backendpools[0].id
              }
            ]
            pipConfiguration: {
              publicIpNameSuffix: '-pip-01'
            }
            skuName: 'Basic'
          }
          {
            name: 'ipconfig2'
            primary: false
            subnetResourceId: virtualNetworks.outputs.subnetResourceIds[0]
            loadBalancerBackendAddressPools: [
              {
                id: loadbalancer.outputs.backendpools[0].id
              }
            ]
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

module vm2 '../modules/Microsoft.Compute/virtualMachines_custom/deploy.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'vm-02'
  params: {
    name: 'vm-02'
    adminUsername: 'admin-vm'
    adminPassword: '${uniqueString(randomGuid)}rpP@340'
    location: location
    availabilitySetResourceId: availabilitySet.outputs.resourceId
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
            loadBalancerBackendAddressPools: [
              {
                id: loadbalancer.outputs.backendpools[0].id
              }
            ]
          }
          {
            name: 'ipconfig2'
            primary: false
            subnetResourceId: virtualNetworks.outputs.subnetResourceIds[0]
            loadBalancerBackendAddressPools: [
              {
                id: loadbalancer.outputs.backendpools[0].id
              }
            ]
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
