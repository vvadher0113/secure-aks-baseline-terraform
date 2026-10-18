module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  name                = local.law_name
  location            = var.location
  resource_group_name = module.spoke_resource_group.name

  log_analytics_workspace_sku               = var.log_analytics_sku
  log_analytics_workspace_retention_in_days = var.log_analytics_retention_days

  tags             = local.default_tags
  enable_telemetry = var.enable_telemetry
}
