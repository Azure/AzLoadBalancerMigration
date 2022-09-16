Describe "ValidateScenario" {
  BeforeEach {
    Import-Module ./AzureBasicLoadBalancerMigration/modules/ValidateScenario/ValidateScenario.psm1 -Force
    $options = [System.Text.Json.JsonSerializerOptions]::new()
    $options.WriteIndented = $true
    $options.IgnoreReadOnlyProperties = $true
    $stdLbJson = @'
          {
              "ProvisioningState": "Succeeded",
              "Sku": {
                "Name": "Basic",
                "Tier": "Regional"
              },
              "FrontendIpConfigurations": [
                {
                  "PrivateIpAddress": "",
                  "PrivateIpAllocationMethod": "Dynamic",
                  "PrivateIpAddressVersion": "IPv4",
                  "ProvisioningState": "Succeeded",
                  "Zones": [],
                  "InboundNatRules": [],
                  "InboundNatPools": [],
                  "OutboundRules": [],
                  "LoadBalancingRules": [
                    {
                      "Id": "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Network/loadBalancers/lb-basic-01/loadBalancingRules/rule-01"
                    }
                  ],
                  "Subnet": {
                    "AddressPrefix": null,
                    "IpConfigurations": [],
                    "ServiceAssociationLinks": [],
                    "ResourceNavigationLinks": [],
                    "NetworkSecurityGroup": null,
                    "RouteTable": null,
                    "NatGateway": null,
                    "ServiceEndpoints": [],
                    "ServiceEndpointPolicies": [],
                    "Delegations": [],
                    "PrivateEndpoints": [],
                    "ProvisioningState": null,
                    "PrivateEndpointNetworkPolicies": null,
                    "PrivateLinkServiceNetworkPolicies": null,
                    "IpAllocations": [],
                    "Name": null,
                    "Etag": null,
                    "Id": "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Network/virtualNetworks/vnet-01/subnets/subnet-01"
                  },
                  "PublicIpAddress": null,
                  "PublicIPPrefix": null,
                  "GatewayLoadBalancer": null,
                  "Name": "fe-01",
                  "Etag": "W/\u00224104014d-4a71-45da-b64a-15d835fc861b\u0022",
                  "Id": "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Network/loadBalancers/lb-basic-01/frontendIPConfigurations/fe-01"
                }
              ],
              "BackendAddressPools": [
                {
                  "ProvisioningState": "Succeeded",
                  "BackendIpConfigurations": [
                    {
                      "PrivateIpAddressVersion": null,
                      "LoadBalancerBackendAddressPools": [],
                      "LoadBalancerInboundNatRules": [],
                      "Primary": false,
                      "ApplicationGatewayBackendAddressPools": [],
                      "ApplicationSecurityGroups": [],
                      "VirtualNetworkTaps": [],
                      "PrivateLinkConnectionProperties": null,
                      "GatewayLoadBalancer": null,
                      "PrivateIpAddress": null,
                      "PrivateIpAllocationMethod": null,
                      "Subnet": null,
                      "PublicIpAddress": null,
                      "ProvisioningState": null,
                      "Name": null,
                      "Etag": null,
                      "Id": "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Compute/virtualMachineScaleSets/vmss-01/virtualMachines/0/networkInterfaces/vmss-01-nic-01configuration-0/ipConfigurations/ipconfig1"
                    }
                  ],
                  "LoadBalancerBackendAddresses": [],
                  "LoadBalancingRules": [
                    {
                      "Id": "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Network/loadBalancers/lb-basic-01/loadBalancingRules/rule-01"
                    }
                  ],
                  "OutboundRule": null,
                  "TunnelInterfaces": [],
                  "Name": "be-01",
                  "Etag": "W/\u00224104014d-4a71-45da-b64a-15d835fc861b\u0022",
                  "Id": "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Network/loadBalancers/lb-basic-01/backendAddressPools/be-01"
                }
              ],
              "LoadBalancingRules": [
                {
                  "Protocol": "Tcp",
                  "LoadDistribution": "Default",
                  "FrontendPort": 80,
                  "BackendPort": 80,
                  "IdleTimeoutInMinutes": 4,
                  "EnableFloatingIP": false,
                  "EnableTcpReset": false,
                  "DisableOutboundSNAT": null,
                  "ProvisioningState": "Succeeded",
                  "FrontendIPConfiguration": {
                    "Id": "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Network/loadBalancers/lb-basic-01/frontendIPConfigurations/fe-01"
                  },
                  "BackendAddressPool": {
                    "Id": "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Network/loadBalancers/lb-basic-01/backendAddressPools/be-01"
                  },
                  "BackendAddressPools": [
                    {
                      "Id": "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Network/loadBalancers/lb-basic-01/backendAddressPools/be-01"
                    }
                  ],
                  "Probe": {
                    "Id": "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Network/loadBalancers/lb-basic-01/probes/probe-01"
                  },
                  "Name": "rule-01",
                  "Etag": "W/\u00224104014d-4a71-45da-b64a-15d835fc861b\u0022",
                  "Id": "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Network/loadBalancers/lb-basic-01/loadBalancingRules/rule-01"
                }
              ],
              "Probes": [
                {
                  "Protocol": "Tcp",
                  "Port": 80,
                  "IntervalInSeconds": 5,
                  "NumberOfProbes": 2,
                  "RequestPath": null,
                  "ProvisioningState": "Succeeded",
                  "LoadBalancingRules": [
                    {
                      "Id": "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Network/loadBalancers/lb-basic-01/loadBalancingRules/rule-01"
                    }
                  ],
                  "Name": "probe-01",
                  "Etag": "W/\u00224104014d-4a71-45da-b64a-15d835fc861b\u0022",
                  "Id": "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Network/loadBalancers/lb-basic-01/probes/probe-01"
                }
              ],
              "InboundNatRules": [],
              "InboundNatPools": [],
              "OutboundRules": [],
              "ExtendedLocation": null,
              "ResourceGroupName": "rg-001-basic-lb-int-single-fe",
              "Location": "australiaeast",
              "ResourceGuid": "5e913af0-76cb-46aa-8ba3-b366f5503bc0",
              "Type": "Microsoft.Network/loadBalancers",
              "Tag": {},
              "Name": "lb-basic-01",
              "Etag": "W/\u00224104014d-4a71-45da-b64a-15d835fc861b\u0022",
              "Id": "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Network/loadBalancers/lb-basic-01"
            }
'@
    $BasicLoadBalancer = [System.Text.Json.JsonSerializer]::Deserialize($stdLbJson, [Microsoft.Azure.Commands.Network.Models.PSLoadBalancer])
  }

  Context "Input Parameters" {
    It "Should fail is an invalid Load Balancer name is supplied" {
      $errMsg = "Cannot validate argument on parameter 'StdLoadBalancerName'.*"
      { Test-SupportedMigrationScenario -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName '_' -ErrorAction Stop } | Should -Throw -ExpectedMessage $errMsg
    }

    It "Should fail if a Standard Load Balancer is supplied" {
      $BasicLoadBalancer.Sku.Name = 'Standard'
      { Test-SupportedMigrationScenario -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName 'std-lb-01' } | Should -Throw -ExpectedMessage "*The load balancer 'lb-basic-01' in resource group 'rg-001-basic-lb-int-single-fe' is SKU 'Standard'. SKU must be Basic!"
    }
  }
  
  Context "VMSS in BackendPools" {
    It "Should fail if the backend pool ip configuration does not contain 'VirtualMachineScaleSet'" {
      $BasicLoadBalancer.BackendAddressPools[0].BackendIpConfigurations[0].Id = "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Compute/banana/vmss-01/virtualMachines/0/networkInterfaces/vmss-01-nic-01configuration-0/ipConfigurations/ipconfig1"
      { Test-SupportedMigrationScenario -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName 'std-lb-01' -ErrorAction Stop } | Should -Throw -ExpectedMessage "*Basic Load Balancer has backend pools that is not virtualMachineScaleSets, exiting"
    }
  }

  Context "Empty BackendPools" {
    It "Should fail if the backend pool(s) have no membership" {
      $BasicLoadBalancer.BackendAddressPools[0].BackendIpConfigurations = @()
      { Test-SupportedMigrationScenario -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName 'std-lb-01' -ErrorAction Stop } | Should -Throw -ExpectedMessage "*Basic Load Balancer has backend pools have no membership, exiting"
    }
  }

  Context "LoadBalancingRules" {
    It "Should fail if no LoadBalancingRules exist on the load balancer" {
      $BasicLoadBalancer.LoadBalancingRules = $null
      { Test-SupportedMigrationScenario -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName 'std-lb-01' -ErrorAction Stop } | Should -Throw -ExpectedMessage "*Load balancer 'lb-basic-01' has no front end configurations, so there is nothing to migrate!"
    }
  }

  Context "Public Ip Prefix" {
    It "Should fail if the Public IP has an IPPrefix" {
      $ipPrefix = [Microsoft.Azure.Commands.Network.Models.PSResourceId]::new()
      $ipPrefix.Id = "/subscriptions/b2375b5f-8dab-4436-b87c-32bc7fdce5d0/resourceGroups/rg-001-basic-lb-int-single-fe/providers/Microsoft.Compute/banana/vmss-01/virtualMachines/0/networkInterfaces/vmss-01-nic-01configuration-0/ipConfigurations/ipconfig1"
      $BasicLoadBalancer.FrontendIpConfigurations[0].PublicIPPrefix = $ipPrefix
      { Test-SupportedMigrationScenario -BasicLoadBalancer $BasicLoadBalancer -StdLoadBalancerName 'std-lb-01' -ErrorAction Stop } | Should -Throw -ExpectedMessage "*FrontEndIPConfiguration*"
    }
  }
  
}