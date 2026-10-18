# ─── Private DNS Zone: AKS Private API Server ────────────────────────────────
# BYO zone so Terraform owns the lifecycle. The AKS managed identity needs
# Private DNS Zone Contributor on this zone (see rbac.tf) so it can create
# the A record for the private API server endpoint.

resource "azurerm_private_dns_zone" "aks_api" {
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = module.spoke_resource_group.name
  tags                = local.default_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks_api_spoke" {
  name                  = "link-aks-api-spoke"
  resource_group_name   = module.spoke_resource_group.name
  private_dns_zone_name = azurerm_private_dns_zone.aks_api.name
  virtual_network_id    = module.spoke_vnet.resource_id
  registration_enabled  = false
  tags                  = local.default_tags
}

# Hub VNet link lets firewall and Bastion resolve the private API server FQDN
resource "azurerm_private_dns_zone_virtual_network_link" "aks_api_hub" {
  name                  = "link-aks-api-hub"
  resource_group_name   = module.spoke_resource_group.name
  private_dns_zone_name = azurerm_private_dns_zone.aks_api.name
  virtual_network_id    = module.hub_vnet.resource_id
  registration_enabled  = false
  tags                  = local.default_tags
}

# ─── Private DNS Zone: Azure Container Registry ──────────────────────────────

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = module.spoke_resource_group.name
  tags                = local.default_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr_spoke" {
  name                  = "link-acr-spoke"
  resource_group_name   = module.spoke_resource_group.name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = module.spoke_vnet.resource_id
  registration_enabled  = false
  tags                  = local.default_tags
}

# Link hub VNet so the firewall and Bastion can resolve the ACR endpoint
resource "azurerm_private_dns_zone_virtual_network_link" "acr_hub" {
  name                  = "link-acr-hub"
  resource_group_name   = module.spoke_resource_group.name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = module.hub_vnet.resource_id
  registration_enabled  = false
  tags                  = local.default_tags
}

# ─── Private DNS Zone: Key Vault ─────────────────────────────────────────────

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = module.spoke_resource_group.name
  tags                = local.default_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv_spoke" {
  name                  = "link-kv-spoke"
  resource_group_name   = module.spoke_resource_group.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = module.spoke_vnet.resource_id
  registration_enabled  = false
  tags                  = local.default_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv_hub" {
  name                  = "link-kv-hub"
  resource_group_name   = module.spoke_resource_group.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = module.hub_vnet.resource_id
  registration_enabled  = false
  tags                  = local.default_tags
}
