# ─── Public IPs ──────────────────────────────────────────────────────────────

resource "azurerm_public_ip" "firewall" {
  name                = "pip-afw-${local.suffix}"
  location            = var.location
  resource_group_name = module.hub_resource_group.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = local.default_tags
}

resource "azurerm_public_ip" "bastion" {
  count               = var.enable_bastion ? 1 : 0
  name                = "pip-bas-${local.suffix}"
  location            = var.location
  resource_group_name = module.hub_resource_group.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = local.default_tags
}

# ─── Azure Firewall Policy ───────────────────────────────────────────────────
# Standard tier; upgrade to Premium for IDPS and TLS inspection in production
# regulated environments.

resource "azurerm_firewall_policy" "main" {
  name                = local.fw_policy_name
  location            = var.location
  resource_group_name = module.hub_resource_group.name
  sku                 = "Standard"
  tags                = local.default_tags

  dns {
    proxy_enabled = true
  }

  insights {
    enabled                            = true
    default_log_analytics_workspace_id = module.log_analytics.resource_id
    retention_in_days                  = 30
  }
}

# ─── Firewall Rule Collections ───────────────────────────────────────────────

resource "azurerm_firewall_policy_rule_collection_group" "aks" {
  name               = "rcg-aks-egress"
  firewall_policy_id = azurerm_firewall_policy.main.id
  priority           = 200

  # Application rules for AKS control plane and image pull traffic
  application_rule_collection {
    name     = "arc-aks-required"
    priority = 210
    action   = "Allow"

    rule {
      name = "aks-fqdn-tag"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses      = [var.spoke_vnet_cidr]
      destination_fqdn_tags = ["AzureKubernetesService"]
    }

    rule {
      name = "microsoft-container-registry"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["mcr.microsoft.com", "*.data.mcr.microsoft.com"]
    }

    # AzureLinux package updates
    rule {
      name = "azurelinux-packages"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["packages.microsoft.com", "*.packages.microsoft.com"]
    }

    rule {
      name = "azure-monitor"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses = [var.spoke_vnet_cidr]
      destination_fqdns = [
        "*.ods.opinsights.azure.com",
        "*.oms.opinsights.azure.com",
        "*.monitoring.azure.com",
      ]
    }

    rule {
      name = "github-container-registry"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["ghcr.io", "*.pkg.github.com"]
    }
  }

  # Network rules for non-HTTP(S) traffic
  network_rule_collection {
    name     = "nrc-aks-required"
    priority = 220
    action   = "Allow"

    rule {
      name              = "ntp"
      protocols         = ["UDP"]
      source_addresses  = [var.spoke_vnet_cidr]
      destination_fqdns = ["ntp.ubuntu.com"]
      destination_ports = ["123"]
    }

    rule {
      name                  = "dns-azure-resolver"
      protocols             = ["UDP", "TCP"]
      source_addresses      = [var.spoke_vnet_cidr]
      destination_addresses = ["168.63.129.16"]
      destination_ports     = ["53"]
    }
  }
}

# ─── Azure Firewall ───────────────────────────────────────────────────────────

resource "azurerm_firewall" "main" {
  name                = local.firewall_name
  location            = var.location
  resource_group_name = module.hub_resource_group.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.main.id
  zones               = ["1", "2", "3"]
  tags                = local.default_tags

  ip_configuration {
    name                 = "ipconfig-01"
    subnet_id            = module.hub_vnet.subnets["AzureFirewallSubnet"].resource_id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  depends_on = [module.log_analytics]
}

# ─── Firewall Diagnostics ────────────────────────────────────────────────────
# Resource-specific destination writes each log category to its own table
# (AZFWApplicationRule, AZFWNetworkRule, AZFWDnsQuery, etc.) for efficient
# KQL queries instead of the generic AzureDiagnostics catch-all.

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                           = "diag-afw-${local.suffix}"
  target_resource_id             = azurerm_firewall.main.id
  log_analytics_workspace_id     = module.log_analytics.resource_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }

  depends_on = [azurerm_firewall.main]
}

# ─── Azure Bastion ────────────────────────────────────────────────────────────
# Optional Standard-tier Bastion for secure SSH/RDP to nodes without a public IP.

resource "azurerm_bastion_host" "main" {
  count               = var.enable_bastion ? 1 : 0
  name                = local.bastion_name
  location            = var.location
  resource_group_name = module.hub_resource_group.name
  sku                 = "Standard"
  tunneling_enabled   = true
  tags                = local.default_tags

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = module.hub_vnet.subnets["AzureBastionSubnet"].resource_id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}
