// service fabric 3 node bronze durability cluster with no management role (MR)
// v0.1

targetScope = 'subscription'
param location string
param resourceGroupName string
param randomGuid string = newGuid()


// @description('Remote desktop user password. Must be a strong password')
// @secure()
// param adminPassword string

// @description('Remote desktop user Id')
// param adminUserName string

@description('Certificate Thumbprint')
param certificateThumbprint string = 'F28CE76CBD99AF46245942B05C9B368BAE9BF226'

#disable-next-line no-hardcoded-env-urls
@description('Refers to the location URL in your key vault where the certificate was uploaded, it is should be in the format of https://<name of the vault>.vault.azure.net:443/secrets/<exact location>')
param certificateUrlValue string = 'https://mtbintkv01.vault.azure.net/secrets/sf/43c3671760204b429ac24fdaf95e01a3'

@description('Name of your cluster - Between 3 and 23 characters. Letters and numbers only')
param clusterName string = resourceGroupName

@description('DNS Name')
param dnsName string = resourceGroupName

@description('Cluster and NodeType 0 Durability Level. see: https://learn.microsoft.com/azure/service-fabric/service-fabric-cluster-capacity#durability-characteristics-of-the-cluster')
@allowed([
  'Bronze'
  'Silver'
  'Gold'
])
param durabilityLevel string = 'Bronze'

@description('Nodetype Network Name')
param nicName string = 'NIC'

@description('Nodetype0 Instance Count')
param nt0InstanceCount int = 3

@description('Nodetype0 Reverse Proxy Port')
param nt0reverseProxyEndpointPort int = 19081

@description('Public IP Address Name')
param publicIPName string = 'PublicIP-LB-FE'

@description('Cluster Reliability Level. see: https://learn.microsoft.com/azure/service-fabric/service-fabric-cluster-capacity#reliability-characteristics-of-the-cluster')
@allowed([
  'Bronze'
  'Silver'
  'Gold'
  'Platinum'
])
param reliabilityLevel string = 'Bronze'

@description('Resource Id of the key vault, is should be in the format of /subscriptions/<Sub ID>/resourceGroups/<Resource group name>/providers/Microsoft.KeyVault/vaults/<vault name>')
param sourceVaultValue string = '/subscriptions/24730882-456b-42df-a6f8-8590ca6e4e37/resourceGroups/rg-core/providers/Microsoft.KeyVault/vaults/mtbintkv01'

@description('Virtual Network Subnet0 Name')
param subnet0Name string = 'Subnet-0'

@description('Virtual Network Subnet0 Address Prefix')
param subnet0Prefix string = '10.0.0.0/24'

@description('Virtual Network Name')
param virtualNetworkName string = 'VNet'

@description('Virtual Machine Image Offer')
param vmImageOffer string = 'WindowsServer'

@description('Virtual Machine OS Type')
param vmOSType string = 'Windows'

@description('Virtual Machine Image Publisher')
param vmImagePublisher string = 'MicrosoftWindowsServer'

@description('Virtual Machine Image SKU')
param vmImageSku string = '2022-Datacenter'

@description('Virtual Machine Image Version')
param vmImageVersion string = 'latest'

@description('Virtual Machine Nodetype0 Name')
@maxLength(9)
param vmNodeType0Name string = 'nt0'

@description('Virtual Machine Nodetype0 Size/SKU')
param vmNodeType0Size string = 'Standard_D2_v2'

@description('Virtual Network address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

// VARIABLES
var nt0applicationEndPort = 30000
var nt0applicationStartPort = 20000
var nt0ephemeralEndPort = 65534
var nt0ephemeralStartPort = 49152
var nt0fabricHttpGatewayPort = 19080
var nt0fabricTcpGatewayPort = 19000

var overProvision = false
var vnetID = resourceId('Microsoft.Network/virtualNetworks', virtualNetworkName)
var subnet0Ref = '${vnetID}/subnets/${subnet0Name}'
var lbName0 = 'LB-${clusterName}-${vmNodeType0Name}'
var lbID0 = resourceId('Microsoft.Network/loadBalancers', lbName0)
var lbIPConfig0 = '${lbID0}/frontendIPConfigurations/LoadBalancerIPConfig'
var lbPoolID0 = '${lbID0}/backendAddressPools/LoadBalancerBEAddressPool'
var lbNatPoolID0 = '${lbID0}/inboundNatPools/LoadBalancerBEAddressNatPool'
var sfTags = {
  resourceType: 'Service Fabric'
  clusterName: clusterName
}

var applicationDiagnosticsStorageAccountName = toLower('sfdiag${uniqueString(subscription().subscriptionId, resourceGroupName, location)}3')
var supportLogStorageAccountName = toLower('sflogs${uniqueString(subscription().subscriptionId, resourceGroupName, location)}2')
var applicationDiagnosticsStorageAccountNameID = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Storage/storageAccounts/${applicationDiagnosticsStorageAccountName}'
var supportLogStorageAccountNameID = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Storage/storageAccounts/${supportLogStorageAccountName}'
var storageAccountType = 'Standard_LRS'
var supportLogStorageAccountType = 'Standard_LRS'
var applicationDiagnosticsStorageAccountType = 'Standard_LRS'
var fqdnSuffix = environment().name =~ 'AzureCloud' ? 'cloudapp.azure.com' : 'cloudapp.usgovcloudapi.net'

// RESOURCES
// used for adminuser and password test env

// Resource Group using modified resourcegroup module that doesnt pass managedBy as it is getting error ResourceGroupManagedByMismatch
module rg '../modules/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: resourceGroupName
  scope: subscription()
  params: {
    name: resourceGroupName
    location: location
    //managedBy: 'test'
  }
}

// sf logs storage account
module supportLogStorageAccount '../modules/Microsoft.Storage/storageAccounts/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-supportLogStorageAccount'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: supportLogStorageAccountName
    location: location
    storageAccountSku: supportLogStorageAccountType
    storageAccountKind: 'StorageV2'
    supportsHttpsTrafficOnly: true
    tags: sfTags
  }
  dependsOn: [
    rg
  ]
}

// sf application/service diagnostic account
module applicationDiagnosticsStorageAccount '../modules/Microsoft.Storage/storageAccounts/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-applicationDiagnosticsStorageAccount'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: applicationDiagnosticsStorageAccountName
    location: location
    storageAccountSku: applicationDiagnosticsStorageAccountType
    storageAccountKind: 'StorageV2'
    supportsHttpsTrafficOnly: true
    tags: sfTags
  }
  dependsOn: [
    rg
  ]
}

// public ip address
module publicIp0 '../modules/Microsoft.Network/publicIpAddresses/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-publicIp-0'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: '${publicIPName}-0'
    location: location
    publicIPAddressVersion: 'IPv4'
    skuTier: 'Regional'
    skuName: 'Basic'
    publicIPAllocationMethod: 'Dynamic'
    domainNameLabel: dnsName
    tags: sfTags
  }
  dependsOn: [
    rg
  ]
}

// vnet and subnet
module virtualNetworks '../modules/Microsoft.Network/virtualNetworks/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-virtualNetworks'
  scope: resourceGroup(resourceGroupName)
  params: {
    // Required parameters
    location: location
    addressPrefixes: [
      vnetAddressPrefix
    ]
    name: virtualNetworkName
    subnets: [
      {
        name: subnet0Name
        addressPrefix: subnet0Prefix
      }
    ]
    tags: sfTags
  }
  dependsOn: [
    rg
  ]
}

// basic lb with public ip
module loadbalancer0 '../modules/Microsoft.Network/loadBalancers_custom/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-lb-basic-0'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: lbName0
    location: location
    frontendIPConfigurations: [
      {
        name: 'LoadBalancerIPConfig'
        publicIPAddressId: publicIp0.outputs.resourceId
      }
    ]
    backendAddressPools: [
      {
        name: 'LoadBalancerBEAddressPool'
      }
    ]
    inboundNatRules: []
    inboundNatPools: []
    loadBalancerSku: 'Basic'
    loadBalancingRules: [
      {
        backendAddressPoolName: 'LoadBalancerBEAddressPool'
        backendPort: nt0fabricTcpGatewayPort
        frontendIPConfigurationName: 'LoadBalancerIPConfig'
        frontendPort: nt0fabricTcpGatewayPort
        idleTimeoutInMinutes: 4
        loadDistribution: 'Default'
        name: 'LBRule'
        probeName: 'FabricGatewayProbe'
        protocol: 'Tcp'
        enableFloatingIP: false
      }
      {
        backendAddressPoolName: 'LoadBalancerBEAddressPool'
        backendPort: nt0fabricHttpGatewayPort
        frontendIPConfigurationName: 'LoadBalancerIPConfig'
        frontendPort: nt0fabricHttpGatewayPort
        idleTimeoutInMinutes: 4
        loadDistribution: 'Default'
        name: 'LBHttpRule'
        probeName: 'FabricHttpGatewayProbe'
        protocol: 'Tcp'
        enableFloatingIP: false
      }
    ]
    probes: [
      {
        intervalInSeconds: 5
        name: 'FabricGatewayProbe'
        numberOfProbes: 2
        port: nt0fabricTcpGatewayPort
        protocol: 'Tcp'
      }
      {
        intervalInSeconds: 5
        name: 'FabricHttpGatewayProbe'
        numberOfProbes: 2
        port: nt0fabricHttpGatewayPort
        protocol: 'Tcp'
      }
    ]
    tags: sfTags
  }
  dependsOn: [
    rg
  ]
}

// virtual machine scaleset service fabric extension
module vmss_serviceFabricExtension '../modules/Microsoft.Compute/virtualMachineScaleSets/extensions/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-ServiceFabricNode'
  scope: resourceGroup(resourceGroupName)
  params: {
    virtualMachineScaleSetName: vmNodeType0Name
    name: '${vmNodeType0Name}_ServiceFabricNode'
    publisher: 'Microsoft.Azure.ServiceFabric'
    type: 'ServiceFabricNode'
    typeHandlerVersion: '1.1'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    protectedSettings: {
      StorageAccountKey1: listKeys(supportLogStorageAccountNameID, '2022-09-01').keys[0].value
      StorageAccountKey2: listKeys(supportLogStorageAccountNameID, '2022-09-01').keys[1].value
    }
    settings: {
      clusterEndpoint: cluster.outputs.endpoint
      nodeTypeRef: vmNodeType0Name
      dataPath: 'D:\\SvcFab'
      durabilityLevel: durabilityLevel
      enableParallelJobs: true
      nicPrefixOverride: subnet0Prefix
      certificate: {
        thumbprint: certificateThumbprint
        x509StoreName: 'My'
      }
    }
  }
  dependsOn: [
    rg
    virtualMachineScaleSets0
  ]
}

// virtual machine scaleset service fabric WAD extension
module vmss_serviceFabricWADExtension '../modules/Microsoft.Compute/virtualMachineScaleSets/extensions/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-VMDiagnosticsVmExt'
  scope: resourceGroup(resourceGroupName)
  params: {
    virtualMachineScaleSetName: vmNodeType0Name
    name: '${vmNodeType0Name}_VMDiagnosticsVmExt'
    publisher: 'Microsoft.Azure.Diagnostics'
    type: 'IaaSDiagnostics'
    typeHandlerVersion: '1.1'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    protectedSettings: {
      storageAccountName: applicationDiagnosticsStorageAccountName
      storageAccountKey: listKeys(applicationDiagnosticsStorageAccountNameID, '2022-09-01').keys[0].value
      storageAccountEndPoint: 'https://${environment().suffixes.storage}'
    }
    settings: {
      WadCfg: {
        DiagnosticMonitorConfiguration: {
          overallQuotaInMB: '50000'
          EtwProviders: {
            EtwEventSourceProviderConfiguration: [
              {
                provider: 'Microsoft-ServiceFabric-Actors'
                scheduledTransferKeywordFilter: '1'
                scheduledTransferPeriod: 'PT5M'
                DefaultEvents: {
                  eventDestination: 'ServiceFabricReliableActorEventTable'
                }
              }
              {
                provider: 'Microsoft-ServiceFabric-Services'
                scheduledTransferPeriod: 'PT5M'
                DefaultEvents: {
                  eventDestination: 'ServiceFabricReliableServiceEventTable'
                }
              }
            ]
            EtwManifestProviderConfiguration: [
              {
                provider: 'cbd93bc2-71e5-4566-b3a7-595d8eeca6e8'
                scheduledTransferLogLevelFilter: 'Information'
                scheduledTransferKeywordFilter: '4611686018427387904'
                scheduledTransferPeriod: 'PT5M'
                DefaultEvents: {
                  eventDestination: 'ServiceFabricSystemEventTable'
                }
              }
            ]
          }
        }
      }
      StorageAccount: applicationDiagnosticsStorageAccountName
    }
  }
  dependsOn: [
    rg
    virtualMachineScaleSets0
  ]
}

// virtual machine scaleset 0
module virtualMachineScaleSets0 '../modules/Microsoft.Compute/virtualMachineScaleSets/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-vmss-0'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: vmNodeType0Name
    location: location
    encryptionAtHost: false
    adminUsername: 'admin-vmss' //adminUserName
    adminPassword: '${uniqueString(randomGuid)}rpP@340' //adminPassword
    enableAutomaticUpdates: false
    enableAutomaticOSUpgrade: true
    osType: vmOSType
    overprovision: overProvision
    skuCapacity: nt0InstanceCount
    skuName: vmNodeType0Size
    vmNamePrefix: vmNodeType0Name
    imageReference: {
      publisher: vmImagePublisher
      offer: vmImageOffer
      sku: vmImageSku
      version: vmImageVersion
    }
    nicConfigurations: [
      {
        ipConfigurations: [
          {
            name: 'ipconfig'
            properties: {
              loadBalancerBackendAddressPools: [
                {
                  id: lbPoolID0
                }
              ]
              subnet: {
                id: subnet0Ref
              }
            }
          }
        ]
        primary: true
        enableAcceleratedNetworking: false
        nicSuffix: '${nicName}-0'
      }
    ]
    osDisk: {
      caching: 'ReadOnly'
      diskSizeGB: '128'
      createOption: 'FromImage'
      managedDisk: {
        storageAccountType: storageAccountType
      }
    }
    secrets: [
      {
        sourceVault: {
          id: sourceVaultValue
        }
        vaultCertificates: [
          {
            certificateStore: 'My'
            certificateUrl: certificateUrlValue
          }
        ]
      }
    ]
    tags: sfTags
  }
  dependsOn: [
    rg
    virtualNetworks
    loadbalancer0
    supportLogStorageAccount
    applicationDiagnosticsStorageAccount
  ]
}

// service fabric cluster
module cluster '../modules/Microsoft.ServiceFabric/clusters/deploy.bicep' = {
  name: '${uniqueString(deployment().name)}-cluster'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: clusterName
    location: location
    addOnFeatures: [
      'DnsService'
      'RepairManager'
    ]
    certificate: {
      thumbprint: certificateThumbprint
      x509StoreName: 'My'
    }
    clientCertificateCommonNames: []
    clientCertificateThumbprints: []
    diagnosticsStorageAccountConfig: {
      blobEndpoint: reference('Microsoft.Storage/storageAccounts/${supportLogStorageAccountName}', '2022-05-01').primaryEndpoints.blob
      protectedAccountKeyName: 'StorageAccountKey1'
      queueEndpoint: reference('Microsoft.Storage/storageAccounts/${supportLogStorageAccountName}', '2022-05-01').primaryEndpoints.queue
      storageAccountName: supportLogStorageAccountName
      tableEndpoint: reference('Microsoft.Storage/storageAccounts/${supportLogStorageAccountName}', '2022-05-01').primaryEndpoints.table
    }
    fabricSettings: [
      {
        parameters: [
          {
            name: 'ClusterProtectionLevel'
            value: 'EncryptAndSign'
          }
        ]
        name: 'Security'
      }
    ]
    managementEndpoint: 'https://${dnsName}.${location}.${fqdnSuffix}:${nt0fabricHttpGatewayPort}'
    nodeTypes: [
      {
        name: vmNodeType0Name
        applicationPorts: {
          endPort: nt0applicationEndPort
          startPort: nt0applicationStartPort
        }
        clientConnectionEndpointPort: nt0fabricTcpGatewayPort
        durabilityLevel: 'Bronze'
        ephemeralPorts: {
          endPort: nt0ephemeralEndPort
          startPort: nt0ephemeralStartPort
        }
        httpGatewayEndpointPort: nt0fabricHttpGatewayPort
        reverseProxyEndpointPort: nt0reverseProxyEndpointPort
        isPrimary: true
        vmInstanceCount: nt0InstanceCount
      }
    ]
    reliabilityLevel: reliabilityLevel
    upgradeMode: 'Automatic'
    vmImage: vmOSType
    tags: sfTags
  }
  dependsOn: [
    rg
    supportLogStorageAccount
  ]
}
