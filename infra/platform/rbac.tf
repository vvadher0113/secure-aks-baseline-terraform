# ─── AKS Control Plane: Private DNS Zone Contributor ─────────────────────────
# Required for the AKS control plane to create the A record for the private
# API server endpoint in the BYO private DNS zone.

resource "azurerm_role_assignment" "aks_dns_zone_contributor" {
  scope                = azurerm_private_dns_zone.aks_api.id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
  principal_type       = "ServicePrincipal"
}

# ─── AKS Control Plane: Network Contributor ──────────────────────────────────
# Required for the control plane to manage load balancer NICs and attach
# them to the AKS subnets under UDR egress.

resource "azurerm_role_assignment" "aks_network_contributor_system" {
  scope                = module.spoke_vnet.subnets["snet-aks-system"].resource_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "aks_network_contributor_user" {
  scope                = module.spoke_vnet.subnets["snet-aks-user"].resource_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
  principal_type       = "ServicePrincipal"
}

# ─── Kubelet Identity: AcrPull ────────────────────────────────────────────────
# Allows nodes to pull images from the private ACR without storing credentials.

resource "azurerm_role_assignment" "acr_pull" {
  scope                = module.acr.resource_id
  role_definition_name = "AcrPull"
  principal_id         = try(module.aks.kubelet_identity.objectId, null)
  principal_type       = "ServicePrincipal"

  depends_on = [module.aks, module.acr]
}

# ─── Kubelet Identity: Key Vault Secrets User ─────────────────────────────────
# Required for the Key Vault CSI driver to read secrets into pods.

resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = module.key_vault.resource_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = try(module.aks.kubelet_identity.objectId, null)
  principal_type       = "ServicePrincipal"

  depends_on = [module.aks, module.key_vault]
}

# ─── Kubelet Identity: Monitoring Metrics Publisher ───────────────────────────
# Required when Container Insights uses managed identity auth (use_aad_auth = true).
# The OMS agent uses the kubelet identity to publish metrics to Azure Monitor.

resource "azurerm_role_assignment" "monitoring_metrics_publisher" {
  scope                = module.aks.resource_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = try(module.aks.kubelet_identity.objectId, null)
  principal_type       = "ServicePrincipal"

  depends_on = [module.aks]
}
