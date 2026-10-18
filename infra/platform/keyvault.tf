module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.11.0"

  name                = local.kv_name
  location            = var.location
  resource_group_name = module.spoke_resource_group.name
  tenant_id           = var.tenant_id
  sku_name            = var.key_vault_sku

  # Purge protection required for HIPAA — prevents permanent deletion within retention window
  purge_protection_enabled   = true
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days

  # Deny all public traffic; allow only the private endpoint
  network_acls = {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = []
    virtual_network_subnet_ids = []
  }

  private_endpoints = {
    pe1 = {
      name                          = "pe-kv-${local.suffix}"
      subnet_resource_id            = module.spoke_vnet.subnets["snet-private-endpoints"].resource_id
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.key_vault.id]
      is_manual_connection          = false
    }
  }

  role_assignments = {
    for idx, oid in var.key_vault_admin_object_ids : "admin_${idx}" => {
      role_definition_id_or_name = "Key Vault Administrator"
      principal_id               = oid
      principal_type             = "Group"
    }
  }

  tags             = local.default_tags
  enable_telemetry = var.enable_telemetry

  depends_on = [azurerm_private_dns_zone_virtual_network_link.kv_spoke]
}
