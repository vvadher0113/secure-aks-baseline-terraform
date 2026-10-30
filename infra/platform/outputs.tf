# Resource Groups

output "hub_resource_group_name" {
  description = "Name of the hub resource group (connectivity resources)."
  value       = module.hub_resource_group.name
}

output "spoke_resource_group_name" {
  description = "Name of the spoke resource group (workload resources)."
  value       = module.spoke_resource_group.name
}

# Networking

output "hub_vnet_id" {
  description = "Resource ID of the hub Virtual Network."
  value       = module.hub_vnet.resource_id
}

output "spoke_vnet_id" {
  description = "Resource ID of the spoke Virtual Network."
  value       = module.spoke_vnet.resource_id
}

output "firewall_private_ip" {
  description = "Private IP address of the Azure Firewall. Used as the UDR next-hop."
  value       = azurerm_firewall.main.ip_configuration[0].private_ip_address
}

# AKS

output "aks_cluster_name" {
  description = "AKS cluster name."
  value       = module.aks.name
}

output "aks_cluster_id" {
  description = "AKS cluster resource ID."
  value       = module.aks.resource_id
}

output "aks_oidc_issuer_url" {
  description = "AKS OIDC issuer URL. Configure federated credentials for Workload Identity here."
  value       = module.aks.oidc_issuer_profile_issuer_url
}

output "aks_private_fqdn" {
  description = "Private FQDN of the AKS API server."
  value       = module.aks.private_fqdn
}

output "aks_get_credentials_cmd" {
  description = "Run this from within the VNet (or via a jump host) to configure kubectl."
  value       = "az aks get-credentials --resource-group ${module.spoke_resource_group.name} --name ${module.aks.name} --overwrite-existing"
}

output "aks_kubelet_identity_object_id" {
  description = "Object ID of the AKS kubelet managed identity."
  value       = try(module.aks.kubelet_identity.objectId, null)
}

output "aks_kubelet_identity_client_id" {
  description = "Client ID of the AKS kubelet managed identity. Use for Workload Identity federation."
  value       = try(module.aks.kubelet_identity.clientId, null)
}

output "aks_control_plane_identity_principal_id" {
  description = "Principal ID of the AKS control plane user-assigned managed identity."
  value       = azurerm_user_assigned_identity.aks.principal_id
}

# ACR

output "acr_login_server" {
  description = "ACR login server URL."
  value       = module.acr.login_server
}

output "acr_name" {
  description = "ACR resource name."
  value       = module.acr.name
}

output "acr_resource_id" {
  description = "ACR resource ID."
  value       = module.acr.resource_id
}

# Key Vault

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = module.key_vault.uri
}

output "key_vault_id" {
  description = "Key Vault resource ID."
  value       = module.key_vault.resource_id
}

# Log Analytics

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace resource ID."
  value       = module.log_analytics.resource_id
}
