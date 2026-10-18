variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID."
}

variable "aks_resource_group_name" {
  type        = string
  description = "Resource group name of the AKS cluster (spoke resource group from stage 1)."
}

variable "aks_cluster_name" {
  type        = string
  description = "AKS cluster name from stage 1."
}

variable "argocd_namespace" {
  type        = string
  description = "Kubernetes namespace where Argo CD will be installed."
  default     = "argocd"
}

variable "argocd_chart_version" {
  type        = string
  description = "Argo CD Helm chart version. Pin to a specific version for reproducibility."
  default     = "7.6.1"
}

variable "gitops_repo_url" {
  type        = string
  description = "HTTPS URL of the Git repository holding the gitops/ manifests."
}

variable "gitops_repo_target_revision" {
  type        = string
  description = "Branch or tag in the GitOps repo to track."
  default     = "main"
}
