locals {
  suffix = "${var.workload}-${var.environment}"

  # Resource names follow Azure CAF conventions
  hub_rg_name       = "rg-hub-${local.suffix}"
  spoke_rg_name     = "rg-spoke-${local.suffix}"
  hub_vnet_name     = "vnet-hub-${local.suffix}"
  spoke_vnet_name   = "vnet-spoke-${local.suffix}"
  firewall_name     = "afw-${local.suffix}"
  fw_policy_name    = "afwp-${local.suffix}"
  bastion_name      = "bas-${local.suffix}"
  aks_name          = "aks-${local.suffix}"
  aks_identity_name = "mi-aks-${local.suffix}"
  law_name          = "law-${local.suffix}"

  # ACR: 5-50 chars, alphanumeric only, globally unique
  acr_name = coalesce(
    var.acr_name,
    substr(lower(replace("acr${var.workload}${var.environment}", "-", "")), 0, 50)
  )

  # Key Vault: 3-24 chars, alphanumeric + hyphens
  kv_name = coalesce(
    var.key_vault_name,
    substr("kv-${local.suffix}", 0, 24)
  )

  default_tags = merge(
    {
      Environment     = var.environment
      Workload        = var.workload
      ManagedBy       = "Terraform"
      ComplianceScope = "HIPAA-HITRUST"
    },
    var.tags
  )
}
