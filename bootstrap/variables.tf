variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID where the Terraform state storage account will be created."
}

variable "location" {
  type        = string
  description = "Azure region for the state storage resource group and storage account."
  default     = "eastus"
}

variable "environment" {
  type        = string
  description = "Short environment label (dev | staging | prod) appended to resource names."
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "workload" {
  type        = string
  description = "Workload short name used as a prefix across all resource names."
  default     = "aksbase"
}

variable "state_storage_restrict_network_access" {
  type        = bool
  description = "When true, the state storage account denies all public network access and only the IPs in state_storage_allowed_ips are permitted. When false (default), public access is allowed so GitHub-hosted runners can reach the backend without additional network setup."
  default     = false
}

variable "state_storage_allowed_ips" {
  type        = list(string)
  description = "IPv4 addresses or CIDR ranges allowed to access the state storage account when state_storage_restrict_network_access is true. Add your operator laptop IP here for local plan/apply during initial bootstrapping."
  default     = []
}
