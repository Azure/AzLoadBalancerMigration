param loadBalancerType string = 'bnasic'
param location string
param subnetId string
param k8sVersion string
param vmSize string

var suffix = uniqueString(resourceGroup().id)

resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-11-01' = {
  name: 'aks-${suffix}'
  location: location
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: 'aks-${suffix}'
    kubernetesVersion: k8sVersion
    networkProfile: {
      networkPlugin: 'azure'
      loadBalancerSku: loadBalancerType
      serviceCidr: '10.1.0.0/24'
      dnsServiceIP: '10.1.0.10'
    }
    agentPoolProfiles: [
      {
        name: 'agentpool1'
        count: 2
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        vnetSubnetID: subnetId
        vmSize: vmSize
        osType: 'Linux'
        osSKU: 'Ubuntu'
      }
    ]
  }
}

