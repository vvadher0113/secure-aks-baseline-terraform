# Hub Resource Group
# Connectivity resources: firewall, bastion, hub VNet

module "hub_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  name             = local.hub_rg_name
  location         = var.location
  tags             = local.default_tags
  enable_telemetry = var.enable_telemetry
}

# Spoke Resource Group
# Workload resources: AKS, ACR, Key Vault, Log Analytics, spoke VNet

module "spoke_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  name             = local.spoke_rg_name
  location         = var.location
  tags             = local.default_tags
  enable_telemetry = var.enable_telemetry
}
