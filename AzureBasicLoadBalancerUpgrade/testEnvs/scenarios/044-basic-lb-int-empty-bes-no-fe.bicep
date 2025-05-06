targetScope = 'resourceGroup'
param randomGuid string = newGuid()
param location string
param resourceGroupName string

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
  ]
}

// basic lb
resource loadbalancer_emptyfe 'Microsoft.Network/loadBalancers@2024-05-01' = {
  name: 'lb-basic-01'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    frontendIPConfigurations: []
    backendAddressPools: []
    inboundNatRules: []
    loadBalancingRules: []
    probes: [] 
    
  }
}
