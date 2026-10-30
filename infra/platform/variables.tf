# Global

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID where all resources will be deployed."
}

variable "tenant_id" {
  type        = string
  description = "Azure Active Directory Tenant ID."
}

variable "location" {
  type        = string
  description = "Primary Azure region for all resources (e.g. eastus, westeurope)."
  default     = "eastus"
}

variable "environment" {
  type        = string
  description = "Environment label appended to all resource names."
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "workload" {
  type        = string
  description = "Short workload name used as a naming prefix."
  default     = "aksbase"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags merged onto every resource."
  default     = {}
}

variable "enable_telemetry" {
  type        = bool
  description = "Enable AVM module telemetry. Set false to opt out."
  default     = true
}

# Networking: Hub

variable "hub_vnet_cidr" {
  type        = string
  description = "Address space for the hub Virtual Network. Must not overlap spoke_vnet_cidr."
  default     = "10.0.0.0/22"
}

variable "firewall_subnet_cidr" {
  type        = string
  description = "CIDR for AzureFirewallSubnet. Azure requires exactly /26 (64 IPs)."
  default     = "10.0.0.0/26"
  validation {
    # Apply the hub VNet prefix length to the subnet's first IP; the resulting
    # network address must match the hub VNet network address.
    condition = cidrhost(
      join("/", [split("/", var.firewall_subnet_cidr)[0], split("/", var.hub_vnet_cidr)[1]]),
      0
    ) == cidrhost(var.hub_vnet_cidr, 0)
    error_message = "firewall_subnet_cidr must fall within hub_vnet_cidr."
  }
}

variable "bastion_subnet_cidr" {
  type        = string
  description = "CIDR for AzureBastionSubnet. Must be /27 or larger; /26 chosen to support Standard Bastion scale units."
  default     = "10.0.0.128/26"
  validation {
    condition = cidrhost(
      join("/", [split("/", var.bastion_subnet_cidr)[0], split("/", var.hub_vnet_cidr)[1]]),
      0
    ) == cidrhost(var.hub_vnet_cidr, 0)
    error_message = "bastion_subnet_cidr must fall within hub_vnet_cidr."
  }
}

variable "enable_bastion" {
  type        = bool
  description = "Deploy Azure Bastion in the hub VNet for secure node access."
  default     = true
}

variable "enable_gateway_subnet" {
  type        = bool
  description = "Reserve GatewaySubnet in the hub VNet for a future VPN or ExpressRoute gateway. No gateway resource is deployed; only the subnet is created."
  default     = false
}

variable "gateway_subnet_cidr" {
  type        = string
  description = "CIDR for GatewaySubnet. Minimum /27 required by Azure. Only used when enable_gateway_subnet = true."
  default     = "10.0.0.192/27"
  validation {
    condition = cidrhost(
      join("/", [split("/", var.gateway_subnet_cidr)[0], split("/", var.hub_vnet_cidr)[1]]),
      0
    ) == cidrhost(var.hub_vnet_cidr, 0)
    error_message = "gateway_subnet_cidr must fall within hub_vnet_cidr."
  }
}

# Networking: Spoke

variable "spoke_vnet_cidr" {
  type        = string
  description = "Address space for the spoke Virtual Network. Must not overlap hub_vnet_cidr."
  default     = "10.1.0.0/20"
}

variable "aks_system_subnet_cidr" {
  type        = string
  description = "CIDR for the AKS system node pool subnet. With CNI Overlay one VNet IP is used per node, not per pod; /24 is sufficient for the fixed system pool."
  default     = "10.1.0.0/24"
  validation {
    condition = cidrhost(
      join("/", [split("/", var.aks_system_subnet_cidr)[0], split("/", var.spoke_vnet_cidr)[1]]),
      0
    ) == cidrhost(var.spoke_vnet_cidr, 0)
    error_message = "aks_system_subnet_cidr must fall within spoke_vnet_cidr."
  }
}

variable "aks_user_subnet_cidr" {
  type        = string
  description = "CIDR for the AKS user node pool subnet. /22 (1024 IPs) supports large autoscaling node counts with room for rolling upgrades."
  default     = "10.1.4.0/22"
  validation {
    condition = cidrhost(
      join("/", [split("/", var.aks_user_subnet_cidr)[0], split("/", var.spoke_vnet_cidr)[1]]),
      0
    ) == cidrhost(var.spoke_vnet_cidr, 0)
    error_message = "aks_user_subnet_cidr must fall within spoke_vnet_cidr."
  }
}

variable "private_endpoint_subnet_cidr" {
  type        = string
  description = "CIDR for the private endpoint subnet (ACR, Key Vault, and other private endpoints)."
  default     = "10.1.8.0/24"
  validation {
    condition = cidrhost(
      join("/", [split("/", var.private_endpoint_subnet_cidr)[0], split("/", var.spoke_vnet_cidr)[1]]),
      0
    ) == cidrhost(var.spoke_vnet_cidr, 0)
    error_message = "private_endpoint_subnet_cidr must fall within spoke_vnet_cidr."
  }
}

# AKS Networking

variable "pod_cidr" {
  type        = string
  description = "Pod CIDR for Azure CNI Overlay. Must not overlap hub_vnet_cidr, spoke_vnet_cidr, or aks_service_cidr. Pods are not routed in the VNet so a 10.x range is safe as long as it does not match any connected on-premises prefix."
  default     = "10.244.0.0/16"
  validation {
    # No overlap: the hub VNet's first IP must not land inside the pod CIDR,
    # and the pod CIDR's first IP must not land inside the hub VNet.
    condition = (
      cidrhost(join("/", [split("/", var.hub_vnet_cidr)[0], split("/", var.pod_cidr)[1]]), 0) != cidrhost(var.pod_cidr, 0) &&
      cidrhost(join("/", [split("/", var.pod_cidr)[0], split("/", var.hub_vnet_cidr)[1]]), 0) != cidrhost(var.hub_vnet_cidr, 0) &&
      cidrhost(join("/", [split("/", var.spoke_vnet_cidr)[0], split("/", var.pod_cidr)[1]]), 0) != cidrhost(var.pod_cidr, 0) &&
      cidrhost(join("/", [split("/", var.pod_cidr)[0], split("/", var.spoke_vnet_cidr)[1]]), 0) != cidrhost(var.spoke_vnet_cidr, 0)
    )
    error_message = "pod_cidr must not overlap hub_vnet_cidr or spoke_vnet_cidr."
  }
  validation {
    condition = (
      cidrhost(join("/", [split("/", var.aks_service_cidr)[0], split("/", var.pod_cidr)[1]]), 0) != cidrhost(var.pod_cidr, 0) &&
      cidrhost(join("/", [split("/", var.pod_cidr)[0], split("/", var.aks_service_cidr)[1]]), 0) != cidrhost(var.aks_service_cidr, 0)
    )
    error_message = "pod_cidr must not overlap aks_service_cidr."
  }
}

variable "aks_service_cidr" {
  type        = string
  description = "CIDR for Kubernetes service VIPs. Must not overlap any VNet address space; this range is never routed outside the cluster."
  default     = "172.16.0.0/16"
  validation {
    condition = (
      cidrhost(join("/", [split("/", var.hub_vnet_cidr)[0], split("/", var.aks_service_cidr)[1]]), 0) != cidrhost(var.aks_service_cidr, 0) &&
      cidrhost(join("/", [split("/", var.aks_service_cidr)[0], split("/", var.hub_vnet_cidr)[1]]), 0) != cidrhost(var.hub_vnet_cidr, 0) &&
      cidrhost(join("/", [split("/", var.spoke_vnet_cidr)[0], split("/", var.aks_service_cidr)[1]]), 0) != cidrhost(var.aks_service_cidr, 0) &&
      cidrhost(join("/", [split("/", var.aks_service_cidr)[0], split("/", var.spoke_vnet_cidr)[1]]), 0) != cidrhost(var.spoke_vnet_cidr, 0)
    )
    error_message = "aks_service_cidr must not overlap hub_vnet_cidr or spoke_vnet_cidr."
  }
}

variable "aks_dns_service_ip" {
  type        = string
  description = "CoreDNS service IP within aks_service_cidr. Must not be the first (.0) or broadcast address of the range."
  default     = "172.16.0.10"
  validation {
    # Apply the service CIDR prefix length to the DNS IP; the network address must match.
    condition = cidrhost(
      join("/", [var.aks_dns_service_ip, split("/", var.aks_service_cidr)[1]]),
      0
    ) == cidrhost(var.aks_service_cidr, 0)
    error_message = "aks_dns_service_ip must fall within aks_service_cidr."
  }
}

variable "aks_network_policy" {
  type        = string
  description = "Network policy engine for AKS pods (calico | cilium)."
  default     = "calico"
  validation {
    condition     = contains(["calico", "cilium"], var.aks_network_policy)
    error_message = "aks_network_policy must be calico or cilium."
  }
}

# Log Analytics

variable "log_analytics_sku" {
  type        = string
  description = "Log Analytics Workspace SKU."
  default     = "PerGB2018"
}

variable "log_analytics_retention_days" {
  type        = number
  description = "Log retention in days. HIPAA requires a minimum of 6 years; set 730 for 2-year hot retention with archival beyond."
  default     = 90
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Retention must be between 30 and 730 days."
  }
}

# Key Vault

variable "key_vault_name" {
  type        = string
  description = "Override the auto-generated Key Vault name (max 24 chars, alphanumeric + hyphens)."
  default     = ""
}

variable "key_vault_sku" {
  type        = string
  description = "Key Vault SKU. Use premium for HSM-backed keys (HIPAA recommendation)."
  default     = "standard"
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "key_vault_sku must be standard or premium."
  }
}

variable "key_vault_soft_delete_retention_days" {
  type        = number
  description = "Soft-delete retention window in days (7-90). HIPAA data retention requires 90."
  default     = 90
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Retention must be between 7 and 90 days."
  }
}

variable "key_vault_admin_object_ids" {
  type        = list(string)
  description = "Azure AD object IDs (users or groups) granted the Key Vault Administrator role."
  default     = []
}

# ACR

variable "acr_name" {
  type        = string
  description = "Override the auto-generated ACR name (5-50 chars, alphanumeric, globally unique)."
  default     = ""
}

variable "acr_geo_replication_locations" {
  type        = list(string)
  description = "Additional regions for ACR geo-replication. Premium SKU only."
  default     = []
}

# AKS

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version. Null selects the latest supported version."
  default     = null
}

variable "automatic_channel_upgrade" {
  type        = string
  description = "AKS automatic upgrade channel (none | patch | rapid | stable | node-image)."
  default     = "stable"
  validation {
    condition     = contains(["none", "patch", "rapid", "stable", "node-image"], var.automatic_channel_upgrade)
    error_message = "Invalid upgrade channel."
  }
}

variable "system_node_pool_vm_size" {
  type        = string
  description = "VM size for the system (critical add-ons) node pool."
  default     = "Standard_D4ds_v5"
}

variable "system_node_pool_count" {
  type        = number
  description = "Fixed node count for the system node pool. Use an odd number for quorum."
  default     = 3
}

variable "system_node_pool_os_disk_size_gb" {
  type        = number
  description = "OS disk size in GB for system pool nodes."
  default     = 128
}

variable "user_node_pool_vm_size" {
  type        = string
  description = "VM size for the user (workload) node pool."
  default     = "Standard_D8ds_v5"
}

variable "user_node_pool_min_count" {
  type        = number
  description = "Autoscaler minimum node count for the user pool."
  default     = 1
}

variable "user_node_pool_max_count" {
  type        = number
  description = "Autoscaler maximum node count for the user pool."
  default     = 10
}

variable "user_node_pool_initial_count" {
  type        = number
  description = "Initial node count for the user pool."
  default     = 3
}

variable "user_node_pool_os_disk_size_gb" {
  type        = number
  description = "OS disk size in GB for user pool nodes."
  default     = 128
}

variable "aks_availability_zones" {
  type        = list(string)
  description = "Availability zones for AKS node pools."
  default     = ["1", "2", "3"]
}

variable "aks_admin_group_object_ids" {
  type        = list(string)
  description = "Azure AD group object IDs granted AKS cluster-admin role via Azure RBAC."
  default     = []
}

variable "aks_defender_enabled" {
  type        = bool
  description = "Enable Microsoft Defender for Containers on the AKS cluster."
  default     = true
}

variable "aks_workload_identity_enabled" {
  type        = bool
  description = "Enable Workload Identity and OIDC issuer on AKS."
  default     = true
}

variable "aks_secret_rotation_enabled" {
  type        = bool
  description = "Enable automatic secret rotation for the Key Vault CSI driver."
  default     = true
}

variable "maintenance_window_day" {
  type        = string
  description = "Day of the week for the AKS maintenance window."
  default     = "Sunday"
}

variable "maintenance_window_hour_utc" {
  type        = number
  description = "UTC start hour for the AKS maintenance window (0-23)."
  default     = 2
  validation {
    condition     = var.maintenance_window_hour_utc >= 0 && var.maintenance_window_hour_utc <= 23
    error_message = "Hour must be between 0 and 23."
  }
}

