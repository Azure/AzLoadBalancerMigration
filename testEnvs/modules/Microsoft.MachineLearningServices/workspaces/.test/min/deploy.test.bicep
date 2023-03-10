targetScope = 'subscription'

// ========== //
// Parameters //
// ========== //

@description('Optional. The name of the resource group to deploy for testing purposes.')
@maxLength(90)
param resourceGroupName string = 'ms.machinelearningservices.workspaces-${serviceShort}-rg'

@description('Optional. The location to deploy resources to.')
param location string = deployment().location

@description('Optional. A short identifier for the kind of deployment. Should be kept short to not run into resource-name length-constraints.')
param serviceShort string = 'mlswmin'

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
    keyVaultName: 'dep-<<namePrefix>>-kv-${serviceShort}'
    applicationInsightsName: 'dep-<<namePrefix>>-appI-${serviceShort}'
    storageAccountName: 'dep<<namePrefix>>st${serviceShort}'
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
    associatedApplicationInsightsResourceId: nestedDependencies.outputs.applicationInsightsResourceId
    associatedKeyVaultResourceId: nestedDependencies.outputs.keyVaultResourceId
    associatedStorageAccountResourceId: nestedDependencies.outputs.storageAccountResourceId
    sku: 'Basic'
    systemAssignedIdentity: true
  }
}
