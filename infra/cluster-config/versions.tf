terraform {
  required_version = ">= 1.11.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.2.0, < 5.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.14.0, < 3.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.31.0, < 3.0.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

# This stage must run from within the spoke VNet (e.g. a self-hosted GitHub
# runner or via `az aks command invoke`) because the AKS API server is private.
# kubelogin is required: https://github.com/Azure/kubelogin
provider "helm" {
  kubernetes {
    host                   = data.azurerm_kubernetes_cluster.platform.kube_config[0].host
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.platform.kube_config[0].cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      args = [
        "get-token",
        "--login", "azurecli",
        "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630",
      ]
    }
  }
}

provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.platform.kube_config[0].host
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.platform.kube_config[0].cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args = [
      "get-token",
      "--login", "azurecli",
      "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630",
    ]
  }
}
