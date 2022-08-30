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
        name: 'subnet1'
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

module publicIp02 '../modules/Microsoft.Network/publicIpAddresses/deploy.bicep' = {
  name: 'pip-02'
  params: {
    name: 'pip-02'
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
module loadbalancer '../modules/Microsoft.Network/loadBalancers/deploy.bicep' = {
  name: 'lb-basic-01'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'lb-basic-01'
    location: location
    frontendIPConfigurations: [
      {
        name: 'fe-01'
        publicIPAddressId: publicIp01.outputs.resourceId
      }
      {
        name: 'fe-02'
        publicIPAddressId: publicIp02.outputs.resourceId
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
      {
        backendAddressPoolName: 'be-01'
        backendPort: 81
        frontendIPConfigurationName: 'fe-02'
        frontendPort: 81
        idleTimeoutInMinutes: 4
        loadDistribution: 'Default'
        name: 'rule-02'
        probeName: 'probe-02'
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
      {
        intervalInSeconds: 5
        name: 'probe-02'
        numberOfProbes: 2
        port: '81'
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

module virtualMachineScaleSets '../modules/Microsoft.Compute/virtualMachineScaleSets/deploy.bicep' = {
  name: 'vmss-01'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    encryptionAtHost: false
    skuCapacity: 1
    upgradePolicyMode: 'Manual'
    // Required parameters
    adminUsername: kv1.getSecret('adminUsername')
    imageReference: {
      offer: 'WindowsServer'
      publisher: 'MicrosoftWindowsServer'
      sku: '2022-Datacenter'
      version: 'latest'
    }
    name: 'vmss-01'
    osDisk: {
      createOption: 'fromImage'
      diskSizeGB: '128'
      managedDisk: {
        storageAccountType: 'Standard_LRS'
      }
    }
    osType: 'Windows'
    skuName: 'Standard_DS1_v2'
    // Non-required parameters
    adminPassword: kv1.getSecret('adminPassword')
    nicConfigurations: [
      {
        ipConfigurations: [
          {
            name: 'ipconfig1'
            properties: {
              subnet: {
                id: virtualNetworks.outputs.subnetResourceIds[0]
              }
              loadBalancerBackendAddressPools: [
                {
                  id: loadbalancer.outputs.backendpools[0].id
                }
              ]
            }
          }
        ]
        nicSuffix: '-nic-01'
      }
    ]
  }
  dependsOn: [
    rg
  ]
}
