targetScope = 'subscription'
param randomGuid string = newGuid()
var location = 'eastus'
var resourceGroupName = 'rg-009-basicLBExtBasicStaticPIP'

// Resource Group
module rg '../modules/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: '${resourceGroupName}-${location}'
  params: {
    name: resourceGroupName
    location: location
  }
}

//pip
module pip '../modules/Microsoft.Network/publicIPAddresses/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-pip'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    skuName: 'Basic'
    name: 'pip'
    publicIPAllocationMethod: 'Static'
  }
  dependsOn: [rg]
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
    name: 'vnet'
    subnets: [
      {
        name: 'subnet1'
        addressPrefix: '10.0.1.0/24'
      }
    ]
  }
  dependsOn: [rg]
}

// basic lb
module loadbalancer '../modules/Microsoft.Network/loadBalancers_custom/deploy.bicep' = {
  name: 'lb-basic01'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'lb-basic01'
    location: location
    frontendIPConfigurations: [
      { 
        name: 'fe1'
        publicIPAddressId: pip.outputs.resourceId
      }
    ]
    backendAddressPools: [
      {
        name: 'be1'
      }
    ]
    inboundNatRules: []
    loadBalancerSku: 'Basic'
    loadBalancingRules: [
      {
        backendAddressPoolName: 'be1'
        backendPort: 80
        frontendIPConfigurationName: 'fe1'
        frontendPort: 80
        idleTimeoutInMinutes: 4
        loadDistribution: 'Default'
        name: 'rule1'
        probeName: 'probe1'
        protocol: 'Tcp'
      }
    ]
    probes: [
      {
        intervalInSeconds: 5
        name: 'probe1'
        numberOfProbes: 2
        port: '80'
        protocol: 'Tcp'
      }
    ]
  }
  dependsOn: [rg]
}

resource kv1 'Microsoft.KeyVault/vaults@2019-09-01' existing = {
  name: 'kvvmss${uniqueString(subscription().id)}'
  scope: resourceGroup('rg-vmsstestingconfig')
}

module virtualMachineScaleSets '../modules/Microsoft.Compute/virtualMachineScaleSets/deploy.bicep' = {
  name: 'vmss'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    encryptionAtHost: false
    skuCapacity: 1
    upgradePolicyMode: 'Manual'
    // Required parameters
    adminUsername: 'admin-vmss'
    imageReference: {
      offer: 'WindowsServer'
      publisher: 'MicrosoftWindowsServer'
      sku: '2022-Datacenter'
      version: 'latest'
    }
    name: 'vmss'
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
    adminPassword: '${uniqueString(randomGuid)}rpP@340'
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
        nicSuffix: '-nic01'
      }
    ]
  }
  dependsOn: [rg]
}
