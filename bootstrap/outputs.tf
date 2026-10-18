output "resource_group_name" {
  description = "Resource group that contains the Terraform state storage account."
  value       = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  description = "Storage account name to use in the azurerm backend configuration."
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Blob container name to use in the azurerm backend configuration."
  value       = azurerm_storage_container.tfstate.name
}

output "backend_config_snippet" {
  description = "Paste these values into backends/platform.hcl and backends/cluster-config.hcl."
  value       = <<-EOT
    resource_group_name  = "${azurerm_resource_group.tfstate.name}"
    storage_account_name = "${azurerm_storage_account.tfstate.name}"
    container_name       = "${azurerm_storage_container.tfstate.name}"
  EOT
}
