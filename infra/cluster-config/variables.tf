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

variable "acr_login_server" {
  type        = string
  description = "Login server of the private ACR from stage 1 (e.g. acraksbaseprod.azurecr.io). Used to set Helm image repositories and to derive the ACR name for az acr import."
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

variable "argocd_apps_chart_version" {
  type        = string
  description = "argocd-apps Helm chart version used to deploy the app-of-apps Application resource."
  default     = "2.0.2"
}

variable "argocd_image_tag" {
  type        = string
  description = "ArgoCD container image tag imported into ACR and set in the Helm chart. Must match the appVersion of argocd_chart_version (chart 7.6.1 ships v2.12.3)."
  default     = "v2.12.3"
}

variable "argocd_redis_image_tag" {
  type        = string
  description = "Redis image tag (docker.io/library/redis) imported into ACR for the ArgoCD bundled Redis cache."
  default     = "7.0.15-alpine"
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
