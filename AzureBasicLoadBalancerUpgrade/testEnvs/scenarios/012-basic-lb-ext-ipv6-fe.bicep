targetScope = 'subscription'
param randomGuid string = newGuid()
param location string
param resourceGroupName string


// Resource Group
module rg '../modules/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: '${resourceGroupName}-${location}'
  params: {
    name: resourceGroupName
    location: location
  }
}

//pip
module pip1 '../modules/Microsoft.Network/publicIPAddresses/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-pip-01'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    skuName: 'Basic'
    name: 'pip-01-v4'
    publicIPAddressVersion: 'IPv4'
  }
  dependsOn: [
    rg
  ]
}

module pip2 '../modules/Microsoft.Network/publicIPAddresses/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-pip-02'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    skuName: 'Basic'
    name: 'pip-02-v6'
    publicIPAddressVersion: 'IPv6'
  }
  dependsOn: [
    rg
  ]
}

// vnet
module virtualNetworks '../modules/vnet/vnet.bicep' = {
  name: '${uniqueString(deployment().name)}-virtualNetworks'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: '${uniqueString(deployment().name)}-virtualNetworks'
    location: location
    vNetAddressPrefixes: [
      '10.0.0.0/16'
      'fd00:db8:deca::/48'
    ]
    subnets: [
      {
        name: 'subnet1'
        properties: {
          addressPrefixes: [
            '10.0.1.0/24'
            'fd00:db8:deca::/64'
          ]
        }
      }
    ]
  }
  dependsOn: [
    rg
  ]
}

// module virtualNetworks '../modules/Microsoft.Network/virtualNetworks/deploy.bicep' = {
//   name: '${uniqueString(deployment().name)}-virtualNetworks'
//   scope: resourceGroup(resourceGroupName)
//   params: {
//     // Required parameters
//     location: location
//     addressPrefixes: [
//       '10.0.0.0/16'
//       'fd00:db8:deca::/48'
//     ]
//     name: 'vnet-01'
//     subnets: [
//       {
//         name: 'subnet1'
//         addressPrefixes: [
//           '10.0.1.0/24'
//           'fd00:db8:deca::/64'
//         ]
//       }
//     ]
//   }
//   dependsOn: [
//     rg
//   ]
// }

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
        publicIPAddressId: pip1.outputs.resourceId
      }
      {
        name: 'fe-02'
        publicIPAddressId: pip2.outputs.resourceId
      }
    ]
    backendAddressPools: [
      {
        name: 'be-01'
      }
      {
        name: 'be-ipv6'
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
        backendAddressPoolName: 'be-ipv6'
        backendPort: 80
        frontendIPConfigurationName: 'fe-02'
        frontendPort: 8080
        idleTimeoutInMinutes: 4
        loadDistribution: 'Default'
        name: 'rule-02'
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


module virtualMachineScaleSets '../modules/Microsoft.Compute/virtualMachineScaleSets/deploy.bicep' = {
  name: 'vmss-01'
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
          {
            name: 'ipconfig2'
            properties: {
              subnet: {
                id: virtualNetworks.outputs.subnetResourceIds[0]
              }
              privateIPAddressVersion: 'IPv6'
              loadBalancerBackendAddressPools: [
                {
                  id: loadbalancer.outputs.backendpools[1].id
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
