targetScope = 'resourceGroup'

@secure()
param adminPassword string = newGuid()
param location string
param resourceGroupName string

resource pip_01 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: 'pip-01'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    ipTags: []
  }
}

resource pip_02 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: 'pip-02'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    ipTags: []
  }
}

resource vnet_01 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: 'vnet-01'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet1'
        properties: {
          addressPrefix: '10.0.1.0/24'
          serviceEndpoints: []
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
    ]
    virtualNetworkPeerings: []
    enableDdosProtection: false
  }
  dependsOn: []
}

resource vmss_01 'Microsoft.Compute/virtualMachineScaleSets@2022-08-01' = {
  name: 'vmss-01'
  location: location
  sku: {
    name: 'Standard_DS1_v2'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    singlePlacementGroup: true
    orchestrationMode: 'Uniform'
    upgradePolicy: {
      mode: 'Manual'
      rollingUpgradePolicy: {
        maxBatchInstancePercent: 20
        maxUnhealthyInstancePercent: 20
        maxUnhealthyUpgradedInstancePercent: 20
        pauseTimeBetweenBatches: 'PT0S'
      }
      automaticOSUpgradePolicy: {
        enableAutomaticOSUpgrade: false
        useRollingUpgradePolicy: false
        disableAutomaticRollback: false
      }
    }
    scaleInPolicy: {
      rules: [
        'Default'
      ]
    }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'vmssvm'
        adminUsername: 'admin-vmss'
        adminPassword: adminPassword
        windowsConfiguration: {
          provisionVMAgent: true
          enableAutomaticUpdates: true
          enableVMAgentPlatformUpdates: false
        }
        secrets: []
        allowExtensionOperations: true
      }
      storageProfile: {
        osDisk: {
          osType: 'Windows'
          createOption: 'FromImage'
          caching: 'None'
          managedDisk: {
            storageAccountType: 'Standard_LRS'
          }
          diskSizeGB: 128
        }
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: '2022-Datacenter'
          version: 'latest'
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'vmss-01-nic-01'
            properties: {
              primary: true
              enableAcceleratedNetworking: true
              disableTcpStateTracking: false
              dnsSettings: {
                dnsServers: []
              }
              enableIPForwarding: false
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    primary: true
                    subnet: {
                      id: resourceId('Microsoft.Network/virtualNetworks/subnets', 'vnet-01', 'subnet1')
                    }
                    privateIPAddressVersion: 'IPv4'
                    loadBalancerBackendAddressPools: [
                      {
                        id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'lb-standard-01', 'be-01')
                      }
                    ]
                    loadBalancerInboundNatPools: [
                      {
                        id: resourceId(
                          'Microsoft.Network/loadBalancers/inboundNatPools',
                          'lb-standard-01',
                          'natpool-01'
                        )
                      }
                    ]
                  }
                }
                {
                  name: 'ipconfig2'
                  properties: {
                    primary: false
                    subnet: {
                      id: resourceId('Microsoft.Network/virtualNetworks/subnets', 'vnet-01', 'subnet1')
                    }
                    privateIPAddressVersion: 'IPv4'
                    loadBalancerBackendAddressPools: [
                      {
                        id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'lb-standard-01', 'be-01')
                      }
                    ]
                    loadBalancerInboundNatPools: [
                      {
                        id: resourceId(
                          'Microsoft.Network/loadBalancers/inboundNatPools',
                          'lb-standard-01',
                          'natpool-02'
                        )
                      }
                    ]
                  }
                }
              ]
            }
          }
          {
            name: 'vmss-01-nic-02'
            properties: {
              primary: false
              enableAcceleratedNetworking: false
              disableTcpStateTracking: false
              dnsSettings: {
                dnsServers: []
              }
              enableIPForwarding: false
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    primary: true
                    subnet: {
                      id: resourceId('Microsoft.Network/virtualNetworks/subnets', 'vnet-01', 'subnet1')
                    }
                    privateIPAddressVersion: 'IPv4'
                    loadBalancerBackendAddressPools: []
                    loadBalancerInboundNatPools: [
                      {
                        id: resourceId(
                          'Microsoft.Network/loadBalancers/inboundNatPools',
                          'lb-standard-01',
                          'natpool-03'
                        )
                      }
                    ]
                  }
                }
                {
                  name: 'ipconfig2'
                  properties: {
                    primary: false
                    subnet: {
                      id: resourceId('Microsoft.Network/virtualNetworks/subnets', 'vnet-01', 'subnet1')
                    }
                    privateIPAddressVersion: 'IPv4'
                    loadBalancerBackendAddressPools: []
                    loadBalancerInboundNatPools: []
                  }
                }
              ]
            }
          }
        ]
      }
      priority: 'Regular'
      scheduledEventsProfile: {}
    }
    additionalCapabilities: {
      ultraSSDEnabled: false
    }
    overprovision: false
    doNotRunExtensionsOnOverprovisionedVMs: false
    platformFaultDomainCount: 2
    automaticRepairsPolicy: {
      enabled: false
      gracePeriod: 'PT30M'
    }
  }
  dependsOn: [
    vnet_01
    lb_standard_01
  ]
}

resource lb_standard_01 'Microsoft.Network/loadBalancers@2022-05-01' = {
  name: 'lb-standard-01'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'fe-01'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: pip_01.id
          }
        }
      }
      {
        name: 'fe-02'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: pip_02.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'be-01'
        properties: {}
      }
      {
        name: 'be-02'
        properties: {}
      }
    ]
    loadBalancingRules: [
      {
        name: 'rule-01'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-standard-01', 'fe-01')
          }
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          protocol: 'Tcp'
          enableTcpReset: false
          loadDistribution: 'Default'
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'lb-standard-01', 'be-01')
          }
          backendAddressPools: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'lb-standard-01', 'be-01')
            }
          ]
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', 'lb-standard-01', 'probe-01')
          }
        }
      }
    ]
    probes: [
      {
        name: 'probe-01'
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 5
          numberOfProbes: 2
          probeThreshold: 1
        }
      }
    ]
    inboundNatRules: []
    inboundNatPools: [
      {
        name: 'natpool-01'
        properties: {
          frontendPortRangeStart: 9080
          frontendPortRangeEnd: 9085
          backendPort: 8080
          protocol: 'Tcp'
          idleTimeoutInMinutes: 4
          enableFloatingIP: false
          enableTcpReset: false
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-standard-01', 'fe-01')
          }
        }
      }
      {
        name: 'natpool-02'
        properties: {
          frontendPortRangeStart: 9180
          frontendPortRangeEnd: 9185
          backendPort: 8180
          protocol: 'Tcp'
          idleTimeoutInMinutes: 4
          enableFloatingIP: false
          enableTcpReset: false
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-standard-01', 'fe-01')
          }
        }
      }
      {
        name: 'natpool-03'
        properties: {
          frontendPortRangeStart: 9280
          frontendPortRangeEnd: 9285
          backendPort: 3389
          protocol: 'Tcp'
          idleTimeoutInMinutes: 4
          enableFloatingIP: false
          enableTcpReset: false
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-standard-01', 'fe-01')
          }
        }
      }
    ]
  }
}
