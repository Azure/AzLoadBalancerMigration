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

module publicIp01 '../modules/Microsoft.Network/publicIPAddresses/deploy.bicep' = {
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
    backendAddressPools: []
    inboundNatRules: [
      {
        name: 'nat-01'
        frontendIPConfigurationName: 'fe-01'
        frontendPort: 81
        backendPort: 81
        protocol: 'Tcp'
      }
    ]
    loadBalancerSku: 'Basic'
    loadBalancingRules: []
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
  dependsOn: [
    rg
  ]
}

module vm '../modules/Microsoft.Compute/virtualMachines_custom/deploy.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'vm-01'
  params: {
    name: 'vm-01'
    adminUsername: 'admin-vm'
    adminPassword: '${uniqueString(randomGuid)}rpP@340'
    availabilitySetResourceId: availabilitySet.outputs.resourceId
    location: location
    imageReference: {
      offer: 'WindowsServer'
      publisher: 'MicrosoftWindowsServer'
      sku: '2022-Datacenter'
      version: 'latest'
    }
    nicConfigurations: [
      {
        location: location
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: virtualNetworks.outputs.subnetResourceIds[0]
            loadBalancerInboundNatRules: [
              {
                id: '${loadbalancer.outputs.resourceId}/inboundNatRules/nat-01'
              }
            ]
            pipConfiguration: {
              publicIpNameSuffix: '-pip-01'
            }
            skuName: 'Basic'
          }
        ]
        nicSuffix: 'nic'
      }
    ]
    osDisk: {
      createOption: 'fromImage'
      diskSizeGB: '128'
      managedDisk: {
        storageAccountType: 'Standard_LRS'
      }
    }
    osType: 'Windows'
    vmSize: 'Standard_DS1_v2'
  }
}
