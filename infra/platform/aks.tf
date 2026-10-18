# ─── AKS Control Plane Identity ──────────────────────────────────────────────
# User-assigned identity gives full lifecycle control and a stable principal_id
# for downstream role assignments (preferable to system-assigned for UDR clusters).

resource "azurerm_user_assigned_identity" "aks" {
  name                = local.aks_identity_name
  location            = var.location
  resource_group_name = module.spoke_resource_group.name
  tags                = local.default_tags
}

# ─── AKS Cluster ─────────────────────────────────────────────────────────────

module "aks" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "0.8.4"

  name      = local.aks_name
  location  = var.location
  parent_id = module.spoke_resource_group.resource_id

  kubernetes_version = var.kubernetes_version

  # ── Identity ─────────────────────────────────────────────────────────────
  managed_identities = {
    system_assigned            = false
    user_assigned_resource_ids = [azurerm_user_assigned_identity.aks.id]
  }

  # ── System Node Pool (critical add-ons only) ──────────────────────────────
  # Tainted with CriticalAddonsOnly so workloads schedule only on user pool.
  default_agent_pool = {
    name                         = "system"
    vm_size                      = var.system_node_pool_vm_size
    count_of                     = var.system_node_pool_count
    os_disk_size_gb              = var.system_node_pool_os_disk_size_gb
    os_disk_type                 = "Ephemeral"
    os_sku                       = "AzureLinux"
    vnet_subnet_id               = module.spoke_vnet.subnets["snet-aks-system"].resource_id
    availability_zones           = var.aks_availability_zones
    enable_auto_scaling          = false
    only_critical_addons_enabled = true
    enable_host_encryption       = true
    node_labels = {
      "nodepool-type" = "system"
    }
    node_taints = ["CriticalAddonsOnly=true:NoSchedule"]
    upgrade_settings = {
      max_surge                     = "25%"
      drain_timeout_in_minutes      = 30
      node_soak_duration_in_minutes = 0
    }
  }

  # ── User Node Pool (application workloads) ────────────────────────────────
  agent_pools = {
    user = {
      name                   = "user"
      vm_size                = var.user_node_pool_vm_size
      count_of               = var.user_node_pool_initial_count
      min_count              = var.user_node_pool_min_count
      max_count              = var.user_node_pool_max_count
      enable_auto_scaling    = true
      os_disk_size_gb        = var.user_node_pool_os_disk_size_gb
      os_disk_type           = "Ephemeral"
      os_sku                 = "AzureLinux"
      vnet_subnet_id         = module.spoke_vnet.subnets["snet-aks-user"].resource_id
      availability_zones     = var.aks_availability_zones
      mode                   = "User"
      enable_host_encryption = true
      node_labels = {
        "nodepool-type" = "user"
      }
      upgrade_settings = {
        max_surge                     = "33%"
        drain_timeout_in_minutes      = 30
        node_soak_duration_in_minutes = 0
      }
    }
  }

  # ── Networking ────────────────────────────────────────────────────────────
  # Azure CNI Overlay: nodes use spoke VNet IPs, pods use a separate CIDR
  # that lives entirely outside the VNet address space. This allows large pod
  # counts without consuming VNet IP addresses.
  # outbound_type = "userDefinedRouting" forces egress through Azure Firewall
  # via the route tables in routes.tf instead of an outbound load balancer.
  network_profile = {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = var.aks_network_policy
    pod_cidr            = var.pod_cidr
    dns_service_ip      = var.aks_dns_service_ip
    service_cidr        = var.aks_service_cidr
    load_balancer_sku   = "standard"
    outbound_type       = "userDefinedRouting"
    ip_families         = ["IPv4"]
  }

  # ── Private Cluster ───────────────────────────────────────────────────────
  # BYO private DNS zone keeps the zone in Terraform state, lets us link the
  # hub VNet so the firewall and Bastion can resolve the API server, and avoids
  # the MC_ resource group dependency that "System" would create.
  api_server_access_profile = {
    enable_private_cluster             = true
    private_dns_zone                   = azurerm_private_dns_zone.aks_api.id
    enable_private_cluster_public_fqdn = false
  }

  # ── Entra ID RBAC ────────────────────────────────────────────────────────
  aad_profile = {
    managed                = true
    enable_azure_rbac      = true
    admin_group_object_ids = var.aks_admin_group_object_ids
  }

  # Disable local Kubernetes accounts — all authentication flows through Entra ID
  disable_local_accounts = true

  # ── Upgrade ──────────────────────────────────────────────────────────────
  auto_upgrade_profile = {
    upgrade_channel         = var.automatic_channel_upgrade
    node_os_upgrade_channel = "NodeImage"
  }

  # ── Workload Identity and OIDC ────────────────────────────────────────────
  oidc_issuer_profile = {
    enabled = var.aks_workload_identity_enabled
  }

  # ── Security Profile ─────────────────────────────────────────────────────
  security_profile = {
    workload_identity = {
      enabled = var.aks_workload_identity_enabled
    }
    defender = var.aks_defender_enabled ? {
      log_analytics_workspace_resource_id = module.log_analytics.resource_id
      security_monitoring = {
        enabled = true
      }
    } : null
  }

  # ── Container Insights ───────────────────────────────────────────────────
  addon_profile_oms_agent = {
    enabled = true
    config = {
      log_analytics_workspace_resource_id = module.log_analytics.resource_id
      use_aad_auth                        = true
    }
  }

  # ── Azure Policy Add-on ───────────────────────────────────────────────────
  addon_profile_azure_policy = {
    enabled = true
  }

  # ── Key Vault Secrets Store CSI Driver ───────────────────────────────────
  addon_profile_key_vault_secrets_provider = {
    enabled = true
    config = {
      enable_secret_rotation = var.aks_secret_rotation_enabled
      rotation_poll_interval = "2m"
    }
  }

  # ── KEDA (Kubernetes Event-Driven Autoscaling) ────────────────────────────
  # Variable renamed workload_autoscaler_profile -> workload_auto_scaler_profile
  # in module 0.8.x. Confirmed against 0.8.4 inputs.
  workload_auto_scaler_profile = {
    keda = {
      enabled = true
    }
  }

  # ── Maintenance Window ────────────────────────────────────────────────────
  maintenanceconfiguration = {
    default = {
      name = "default"
      time_in_week = [
        {
          day        = var.maintenance_window_day
          hour_slots = [var.maintenance_window_hour_utc]
        }
      ]
    }
  }

  tags             = local.default_tags
  enable_telemetry = var.enable_telemetry

  depends_on = [
    azurerm_role_assignment.aks_network_contributor_system,
    azurerm_role_assignment.aks_network_contributor_user,
    azurerm_role_assignment.aks_dns_zone_contributor,
    azurerm_subnet_route_table_association.aks_system,
    azurerm_subnet_route_table_association.aks_user,
    azurerm_private_dns_zone_virtual_network_link.aks_api_spoke,
  ]
}
