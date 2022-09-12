$rg = 'BasicLB'
$location = 'centralus'
$vnetName = 'BasicLB-VNet'
$vnetAddressPrefix = '10.130.0.0/16'

$subnetBasicLBName = 'VMSS-Subnet'
$subnetBasicLBAddressPrefix = '10.130.2.0/24'

$lbIPName = 'BasicLB-LoadBalancer-PIP'
$lbName = 'BasicLB-LoadBalancer'

$vmssBasicLBName = 'BasicLB-VMSS'

# Delete the resource group
az group delete --name $rg -y

##########################################
# Create Azure Resource Group
##########################################
# Create the resource group
az group create --name $rg --location $location


##########################################
# Create Azure Virtual Network and Subnets
##########################################
# VNet creation
az network vnet create `
    --resource-group $rg `
    --name $vnetName `
    --address-prefixes $vnetAddressPrefix

# Subnet BasicLB
az network vnet subnet create `
    --resource-group $rg `
    --vnet-name $vnetName `
    --name $subnetBasicLBName `
    --address-prefixes $subnetBasicLBAddressPrefix

############################################################
# Create Azure Virtual Public Load Balancer for BasicLB VMSS
############################################################
# Create Azure Load Balancer Public IP
az network public-ip create `
    --resource-group $rg `
    --name $lbIPName `
    --sku 'Basic'

# Create Azure Load Balancer for BasicLB VMSS
az network lb create `
    --resource-group $rg `
    --name $lbName `
    --sku Basic `
    --public-ip-address $lbIPName `
    --frontend-ip-name $lbIPName `
    --backend-pool-name $vmssBasicLBName

# Create Azure Load Balancer Probe HTTP
az network lb probe create `
    --resource-group $rg `
    --lb-name $lbName `
    --name $vmssBasicLBName"-HealthProbe-HTTP" `
    --protocol tcp `
    --port 80

# Create Azure Load Balancer Rule HTTP
az network lb rule create `
    --resource-group $rg `
    --lb-name $lbName `
    --name HTTP `
    --protocol tcp `
    --frontend-port 80 `
    --backend-port 80 `
    --frontend-ip-name $lbIPName `
    --backend-pool-name $vmssBasicLBName `
    --probe-name $vmssBasicLBName"-HealthProbe-HTTP"

# Create Azure Load Balancer Probe HTTPs
az network lb probe create `
    --resource-group $rg `
    --lb-name $lbName `
    --name $vmssBasicLBName"-HealthProbe-HTTPs" `
    --protocol tcp `
    --port 443

# Create Azure Load Balancer Rule HTTPs
az network lb rule create `
    --resource-group $rg `
    --lb-name $lbName `
    --name HTTPs `
    --protocol tcp `
    --frontend-port 443 `
    --backend-port 443 `
    --frontend-ip-name $lbIPName `
    --backend-pool-name $vmssBasicLBName `
    --probe-name $vmssBasicLBName"-HealthProbe-HTTPs"

# Create Azure Load Balancer NAT Rule
az network lb inbound-nat-rule create `
    --resource-group $rg `
    --name 'SSH' `
    --lb-name $lbName `
    --protocol Tcp `
    --frontend-port-range-start 2222 `
    --frontend-port-range-end 2230 `
    --backend-port 22 `
    --frontend-ip-name $lbIPName `
    --backend-pool-name $vmssBasicLBName

############################################################
# Create Azure Virtual Machine Scale Set for BasicLB
############################################################
# Create Network Security Group for BasicLB VMSS
# az network nsg create `
#     --resource-group $rg `
#     --name $vmssBasicLBName"-NSG"

# # Create Network Security Group Rule for BasicLB VMSS
# az network nsg rule create `
#     --resource-group $rg `
#     --nsg-name $vmssBasicLBName"-NSG" `
#     --name 'HTTP' `
#     --protocol '*' `
#     --direction inbound `
#     --source-address-prefix '*' `
#     --source-port-range '*' `
#     --destination-address-prefix '*' `
#     --destination-port-range 80 `
#     --access allow `
#     --priority 200

# az network nsg rule create `
#     --resource-group $rg `
#     --nsg-name $vmssBasicLBName"-NSG" `
#     --name 'HTTPs' `
#     --protocol '*' `
#     --direction inbound `
#     --source-address-prefix '*' `
#     --source-port-range '*' `
#     --destination-address-prefix '*' `
#     --destination-port-range 443 `
#     --access allow `
#     --priority 201

# Create VMSS BasicLB Flexible
az vmss create `
    --resource-group $rg `
    --name $vmssBasicLBName `
    --image UbuntuLTS `
    --upgrade-policy-mode Manual `
    --vm-sku Standard_A0 `
    --instance-count 2 `
    --admin-username victor `
    --admin-password "H2OBarrentA@" `
    --load-balancer $lbName `
    --vnet-name $vnetName `
    --vnet-address-prefix $vnetAddressPrefix `
    --subnet $subnetBasicLBName `
    --subnet-address-prefix $subnetBasicLBAddressPrefix