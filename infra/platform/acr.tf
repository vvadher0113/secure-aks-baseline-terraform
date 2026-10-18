module "acr" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "0.8.0"

  name                = local.acr_name
  location            = var.location
  resource_group_name = module.spoke_resource_group.name
  sku                 = "Premium"

  # Admin credentials disabled; AKS authenticates via kubelet managed identity
  admin_enabled = false

  # Public network access disabled; all traffic via private endpoint
  public_network_access_enabled = false

  # Zone redundancy for HA (Premium SKU)
  zone_redundancy_enabled = true

  georeplications = [
    for loc in var.acr_geo_replication_locations : {
      location                = loc
      zone_redundancy_enabled = true
      tags                    = local.default_tags
    }
  ]

  private_endpoints = {
    pe1 = {
      name                          = "pe-acr-${local.suffix}"
      subnet_resource_id            = module.spoke_vnet.subnets["snet-private-endpoints"].resource_id
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.acr.id]
      is_manual_connection          = false
    }
  }

  tags             = local.default_tags
  enable_telemetry = var.enable_telemetry

  depends_on = [azurerm_private_dns_zone_virtual_network_link.acr_spoke]
}
