targetScope = 'subscription'

// ========== //
// Parameters //
// ========== //

@description('Optional. The name of the resource group to deploy for testing purposes.')
@maxLength(90)
param resourceGroupName string = 'ms.devtestlab.labs-${serviceShort}-rg'

@description('Optional. The location to deploy resources to.')
param location string = deployment().location

@description('Optional. A short identifier for the kind of deployment. Should be kept short to not run into resource-name length-constraints.')
param serviceShort string = 'dtllcom'

@description('Generated. Used as a basis for unique resource names.')
param baseTime string = utcNow('u')

@description('Optional. Enable telemetry via a Globally Unique Identifier (GUID).')
param enableDefaultTelemetry bool = true

// ============ //
// Dependencies //
// ============ //

// General resources
// =================
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

module nestedDependencies 'dependencies.bicep' = {
  scope: resourceGroup
  name: '${uniqueString(deployment().name, location)}-nestedDependencies'
  params: {
    managedIdentityName: 'dep-<<namePrefix>>-msi-${serviceShort}'
    // Adding base time to make the name unique as purge protection must be enabled (but may not be longer than 24 characters total)
    keyVaultName: 'dep-<<namePrefix>>-kv-${serviceShort}-${substring(uniqueString(baseTime), 0, 3)}'
    diskEncryptionSetName: 'dep-<<namePrefix>>-des-${serviceShort}'
    storageAccountName: 'dep<<namePrefix>>sa${serviceShort}'
    virtualNetworkName: 'dep-<<namePrefix>>-vnet-${serviceShort}'
  }
}

// ============== //
// Test Execution //
// ============== //

module testDeployment '../../deploy.bicep' = {
  scope: resourceGroup
  name: '${uniqueString(deployment().name, location)}-test-${serviceShort}'
  params: {
    enableDefaultTelemetry: enableDefaultTelemetry
    name: '<<namePrefix>>${serviceShort}001'
    location: resourceGroup.location
    lock: 'CanNotDelete'
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Reader'
        principalIds: [
          nestedDependencies.outputs.managedIdentityPrincipalId
        ]
        principalType: 'ServicePrincipal'
      }
    ]
    tags: {
      resourceType: 'DevTest Lab'
      labName: '<<namePrefix>>${serviceShort}001'
    }
    announcement: {
      enabled: 'Enabled'
      expirationDate: '2025-12-30T13:00:00.000Z'
      markdown: 'DevTest Lab announcement text. <br> New line. It also supports Markdown'
      title: 'DevTest announcement title'
    }
    environmentPermission: 'Contributor'
    extendedProperties: {
      RdpConnectionType: '7'
    }
    labStorageType: 'Premium'
    artifactsStorageAccount: nestedDependencies.outputs.storageAccountResourceId
    premiumDataDisks: 'Enabled'
    support: {
      enabled: 'Enabled'
      markdown: 'DevTest Lab support text. <br> New line. It also supports Markdown'
    }
    userAssignedIdentities: {
      '${nestedDependencies.outputs.managedIdentityResourceId}': {}
    }
    managementIdentities: {
      '${nestedDependencies.outputs.managedIdentityResourceId}': {}
    }
    vmCreationResourceGroupId: resourceGroup.id
    browserConnect: 'Enabled'
    disableAutoUpgradeCseMinorVersion: true
    isolateLabResources: 'Enabled'
    encryptionType: 'EncryptionAtRestWithCustomerKey'
    encryptionDiskEncryptionSetId: nestedDependencies.outputs.diskEncryptionSetResourceId
    virtualNetworks: [
      {
        name: nestedDependencies.outputs.virtualNetworkName
        externalProviderResourceId: nestedDependencies.outputs.virtualNetworkResourceId
        description: 'lab virtual network description'
        allowedSubnets: [
          {
            labSubnetName: nestedDependencies.outputs.subnetName
            resourceId: nestedDependencies.outputs.subnetResourceId
            allowPublicIp: 'Allow'
          }
        ]
        subnetOverrides: [
          {
            labSubnetName: nestedDependencies.outputs.subnetName
            resourceId: nestedDependencies.outputs.subnetResourceId
            useInVmCreationPermission: 'Allow'
            usePublicIpAddressPermission: 'Allow'
            sharedPublicIpAddressConfiguration: {
              allowedPorts: [
                {
                  transportProtocol: 'Tcp'
                  backendPort: 3389
                }
                {
                  transportProtocol: 'Tcp'
                  backendPort: 22
                }
              ]
            }
          }
        ]
      }
    ]
    policies: [
      {
        name: nestedDependencies.outputs.subnetName
        evaluatorType: 'MaxValuePolicy'
        factData: nestedDependencies.outputs.subnetResourceId
        factName: 'UserOwnedLabVmCountInSubnet'
        threshold: '1'
      }
      {
        name: 'MaxVmsAllowedPerUser'
        evaluatorType: 'MaxValuePolicy'
        factName: 'UserOwnedLabVmCount'
        threshold: '2'
      }
      {
        name: 'MaxPremiumVmsAllowedPerUser'
        evaluatorType: 'MaxValuePolicy'
        factName: 'UserOwnedLabPremiumVmCount'
        status: 'Disabled'
        threshold: '1'
      }
      {
        name: 'MaxVmsAllowedPerLab'
        evaluatorType: 'MaxValuePolicy'
        factName: 'LabVmCount'
        threshold: '3'
      }
      {
        name: 'MaxPremiumVmsAllowedPerLab'
        evaluatorType: 'MaxValuePolicy'
        factName: 'LabPremiumVmCount'
        threshold: '2'
      }
      {
        name: 'AllowedVmSizesInLab'
        evaluatorType: 'AllowedValuesPolicy'
        factData: ''
        factName: 'LabVmSize'
        threshold: ' ${string('["Basic_A0","Basic_A1"]')}'
        status: 'Enabled'
      }
      {
        name: 'ScheduleEditPermission'
        evaluatorType: 'AllowedValuesPolicy'
        factName: 'ScheduleEditPermission'
        threshold: ' ${string('["None","Modify"]')}'
      }
      {
        name: 'GalleryImage'
        evaluatorType: 'AllowedValuesPolicy'
        factName: 'GalleryImage'
        threshold: ' ${string('["{\\"offer\\":\\"WindowsServer\\",\\"publisher\\":\\"MicrosoftWindowsServer\\",\\"sku\\":\\"2019-Datacenter-smalldisk\\",\\"osType\\":\\"Windows\\",\\"version\\":\\"latest\\"}","{\\"offer\\":\\"WindowsServer\\",\\"publisher\\":\\"MicrosoftWindowsServer\\",\\"sku\\":\\"2022-datacenter-smalldisk\\",\\"osType\\":\\"Windows\\",\\"version\\":\\"latest\\"}"]')}'
      }
      {
        name: 'EnvironmentTemplate'
        description: 'Public Environment Policy'
        evaluatorType: 'AllowedValuesPolicy'
        factName: 'EnvironmentTemplate'
        threshold: ' ${string('[""]')}'
      }
    ]
    schedules: [
      {
        name: 'LabVmsShutdown'
        taskType: 'LabVmsShutdownTask'
        status: 'Enabled'
        timeZoneId: 'AUS Eastern Standard Time'
        dailyRecurrence: {
          time: '0000'
        }
        notificationSettingsStatus: 'Enabled'
        notificationSettingsTimeInMinutes: 30
      }
      {
        name: 'LabVmAutoStart'
        taskType: 'LabVmsStartupTask'
        status: 'Enabled'
        timeZoneId: 'AUS Eastern Standard Time'
        weeklyRecurrence: {
          time: '0700'
          weekdays: [
            'Monday'
            'Tuesday'
            'Wednesday'
            'Thursday'
            'Friday'
          ]
        }
      }
    ]
    notificationChannels: [
      {
        name: 'autoShutdown'
        description: 'Integration configured for auto-shutdown'
        events: [
          {
            eventName: 'AutoShutdown'
          }
        ]
        emailRecipient: 'mail@contosodtlmail.com'
        webHookUrl: 'https://webhook.contosotest.com'
        notificationLocale: 'en'
      }
      {
        name: 'costThreshold'
        events: [
          {
            eventName: 'Cost'
          }
        ]
        webHookUrl: 'https://webhook.contosotest.com'
      }
    ]
    artifactSources: [
      {
        name: 'Public Repo'
        displayName: 'Public Artifact Repo'
        status: 'Disabled'
        uri: 'https://github.com/Azure/azure-devtestlab.git'
        sourceType: 'GitHub'
        branchRef: 'master'
        folderPath: '/Artifacts'
      }
      {
        name: 'Public Environment Repo'
        displayName: 'Public Environment Repo'
        status: 'Disabled'
        uri: 'https://github.com/Azure/azure-devtestlab.git'
        sourceType: 'GitHub'
        branchRef: 'master'
        armTemplateFolderPath: '/Environments'
      }
    ]
    costs: {
      status: 'Enabled'
      cycleType: 'CalendarMonth'
      target: 450
      thresholdValue100DisplayOnChart: 'Enabled'
      thresholdValue100SendNotificationWhenExceeded: 'Enabled'
    }
  }
}
