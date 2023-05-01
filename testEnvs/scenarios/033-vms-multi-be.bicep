targetScope = 'subscription'
param location string
param randomGuid string = newGuid()
param resourceGroupName string

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
        name: 'subnet1'
        addressPrefix: '10.0.1.0/24'
      }
    ]
  }
  dependsOn: [ 
    rg 
  ]
}

// basic lb
module loadbalancer '../modules/Microsoft.Network/loadBalancers_custom/deploy.bicep' = {
  name: 'lb-basic-01'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'lb-basic-01'
    location: location
    frontendIPConfigurations: [
      {
        name: 'fe-01'
        subnetId: virtualNetworks.outputs.subnetResourceIds[0]
      }
    ]
    backendAddressPools: [
      {
        name: 'be-01'
      }
      {
        name: 'be-02'
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

module vm '../modules/Microsoft.Compute/virtualMachines_custom/deploy.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'vm-01'
  params: {
    adminUsername: 'admin-vm'
    adminPassword: '${uniqueString(randomGuid)}rpP@340'
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
            primary: true
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
                id: loadbalancer.outputs.backendpools[1].id
              }
            ]
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
