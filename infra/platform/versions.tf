terraform {
  required_version = ">= 1.11.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 4.81.0 is the effective floor driven by AVM modules avm-res-containerservice-managedcluster 0.8.4
      # and avm-res-network-virtualnetwork 0.20.0.
      version = ">= 4.81.0, < 5.0.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.9.0, < 3.0.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.50.0, < 3.10.1"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0, < 4.0.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azuread" {
  tenant_id = var.tenant_id
}
