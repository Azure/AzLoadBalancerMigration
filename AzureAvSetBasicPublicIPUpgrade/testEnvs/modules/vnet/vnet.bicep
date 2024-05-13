param name string
param location string
param vNetAddressPrefixes array
param subnets array

resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' = {
  name: name
  location: location
  properties: {

    addressSpace: {
      addressPrefixes: vNetAddressPrefixes
    }
    subnets: subnets
  }
}

output subnetResourceIds array = [for subnet in subnets: az.resourceId('Microsoft.Network/virtualNetworks/subnets', name, subnet.name)]
