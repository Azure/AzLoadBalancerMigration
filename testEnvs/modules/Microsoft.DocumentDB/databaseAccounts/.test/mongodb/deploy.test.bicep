targetScope = 'subscription'

// ========== //
// Parameters //
// ========== //

@description('Optional. The name of the resource group to deploy for testing purposes.')
@maxLength(90)
param resourceGroupName string = 'ms.documentdb.databaseaccounts-${serviceShort}-rg'

@description('Optional. The location to deploy resources to.')
param location string = deployment().location

@description('Optional. A short identifier for the kind of deployment. Should be kept short to not run into resource-name length-constraints.')
param serviceShort string = 'dddamng'

@description('Optional. Enable telemetry via a Globally Unique Identifier (GUID).')
param enableDefaultTelemetry bool = true

// ============ //
// Dependencies //
// ============ //

// General resources
// =================
resource resourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
}

module nestedDependencies 'dependencies.bicep' = {
  scope: resourceGroup
  name: '${uniqueString(deployment().name, location)}-nestedDependencies'
  params: {
    managedIdentityName: 'dep-<<namePrefix>>-msi-${serviceShort}'
  }
}

// Diagnostics
// ===========
module diagnosticDependencies '../../../../.shared/dependencyConstructs/diagnostic.dependencies.bicep' = {
  scope: resourceGroup
  name: '${uniqueString(deployment().name, location)}-diagnosticDependencies'
  params: {
    storageAccountName: 'dep<<namePrefix>>diasa${serviceShort}01'
    logAnalyticsWorkspaceName: 'dep-<<namePrefix>>-law-${serviceShort}'
    eventHubNamespaceEventHubName: 'dep-<<namePrefix>>-evh-${serviceShort}'
    eventHubNamespaceName: 'dep-<<namePrefix>>-evhns-${serviceShort}'
    location: location
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
    locations: [
      {
        failoverPriority: 0
        isZoneRedundant: false
        locationName: 'West Europe'
      }
      {
        failoverPriority: 1
        isZoneRedundant: false
        locationName: 'North Europe'
      }
    ]
    diagnosticStorageAccountId: diagnosticDependencies.outputs.storageAccountResourceId
    diagnosticWorkspaceId: diagnosticDependencies.outputs.logAnalyticsWorkspaceResourceId
    diagnosticEventHubAuthorizationRuleId: diagnosticDependencies.outputs.eventHubAuthorizationRuleId
    diagnosticEventHubName: diagnosticDependencies.outputs.eventHubNamespaceEventHubName
    diagnosticLogsRetentionInDays: 7
    location: location
    mongodbDatabases: [
      {
        collections: [
          {
            indexes: [
              {
                key: {
                  keys: [
                    '_id'
                  ]
                }
              }
              {
                key: {
                  keys: [
                    '$**'
                  ]
                }
              }
              {
                key: {
                  keys: [
                    'car_id'
                    'car_model'
                  ]
                }
                options: {
                  unique: true
                }
              }
              {
                key: {
                  keys: [
                    '_ts'
                  ]
                }
                options: {
                  expireAfterSeconds: 2629746
                }
              }
            ]
            name: 'car_collection'
            shardKey: {
              car_id: 'Hash'
            }
          }
          {
            indexes: [
              {
                key: {
                  keys: [
                    '_id'
                  ]
                }
              }
              {
                key: {
                  keys: [
                    '$**'
                  ]
                }
              }
              {
                key: {
                  keys: [
                    'truck_id'
                    'truck_model'
                  ]
                }
                options: {
                  unique: true
                }
              }
              {
                key: {
                  keys: [
                    '_ts'
                  ]
                }
                options: {
                  expireAfterSeconds: 2629746
                }
              }
            ]
            name: 'truck_collection'
            shardKey: {
              truck_id: 'Hash'
            }
          }
        ]
        name: '<<namePrefix>>-mdb-${serviceShort}-001'
      }
      {
        collections: [
          {
            indexes: [
              {
                key: {
                  keys: [
                    '_id'
                  ]
                }
              }
              {
                key: {
                  keys: [
                    '$**'
                  ]
                }
              }
              {
                key: {
                  keys: [
                    'bike_id'
                    'bike_model'
                  ]
                }
                options: {
                  unique: true
                }
              }
              {
                key: {
                  keys: [
                    '_ts'
                  ]
                }
                options: {
                  expireAfterSeconds: 2629746
                }
              }
            ]
            name: 'bike_collection'
            shardKey: {
              bike_id: 'Hash'
            }
          }
          {
            indexes: [
              {
                key: {
                  keys: [
                    '_id'
                  ]
                }
              }
              {
                key: {
                  keys: [
                    '$**'
                  ]
                }
              }
              {
                key: {
                  keys: [
                    'bicycle_id'
                    'bicycle_model'
                  ]
                }
                options: {
                  unique: true
                }
              }
              {
                key: {
                  keys: [
                    '_ts'
                  ]
                }
                options: {
                  expireAfterSeconds: 2629746
                }
              }
            ]
            name: 'bicycle_collection'
            shardKey: {
              bicycle_id: 'Hash'
            }
          }
        ]
        name: '<<namePrefix>>-mdb-${serviceShort}-002'
      }
    ]
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Reader'
        principalIds: [
          nestedDependencies.outputs.managedIdentityPrincipalId
        ]
        principalType: 'ServicePrincipal'
      }
    ]
    systemAssignedIdentity: true
  }
}
