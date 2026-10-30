locals {
  acr_name = split(".", var.acr_login_server)[0]
}

data "azurerm_kubernetes_cluster" "platform" {
  name                = var.aks_cluster_name
  resource_group_name = var.aks_resource_group_name
}

# ACR Image Import
# Copies ArgoCD and Redis images from their upstream registries into the private
# ACR so nodes never pull from the internet at runtime. Uses the az acr import
# control-plane API, which does not require VNet connectivity. Re-runs whenever
# the chart version or image tags change.
# Prerequisite: the identity running Terraform must have AcrPush on the ACR.

resource "terraform_data" "argocd_images" {
  triggers_replace = {
    chart_version = var.argocd_chart_version
    acr           = var.acr_login_server
    argocd_tag    = var.argocd_image_tag
    redis_tag     = var.argocd_redis_image_tag
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -e
      az acr import \
        --name "${local.acr_name}" \
        --source "quay.io/argoproj/argocd:${var.argocd_image_tag}" \
        --image "argoproj/argocd:${var.argocd_image_tag}" \
        --force
      az acr import \
        --name "${local.acr_name}" \
        --source "docker.io/library/redis:${var.argocd_redis_image_tag}" \
        --image "library/redis:${var.argocd_redis_image_tag}" \
        --force
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# Argo CD Namespace

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Argo CD Installation
# Installed from the official Helm chart with images served from the private ACR.
# SSO is not configured in this baseline. The initial admin password is stored
# in the argocd-initial-admin-secret Secret in the argocd namespace. Retrieve it:
#   kubectl -n argocd get secret argocd-initial-admin-secret \
#     -o jsonpath="{.data.password}" | base64 -d

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  cleanup_on_fail  = true
  create_namespace = false

  values = [
    yamlencode({
      global = {
        domain = "argocd.internal"
        image = {
          repository = "${var.acr_login_server}/argoproj/argocd"
          tag        = var.argocd_image_tag
        }
      }
      redis = {
        image = {
          repository = "${var.acr_login_server}/library/redis"
          tag        = var.argocd_redis_image_tag
        }
      }
      dex = {
        enabled = false
      }
      server = {
        service = {
          type = "ClusterIP"
        }
        # Disable Argo CD's own TLS termination; terminate at ingress/LB
        extraArgs = ["--insecure"]
      }
      configs = {
        params = {
          # Enforce RBAC and log denied requests. SSO is not configured in this
          # baseline; the initial admin secret is used until an OIDC connector
          # (such as Dex with Entra ID) is added.
          "server.rbac.log.enforce.enable" = "true"
        }
        cm = {
          "application.resourceTrackingMethod"                     = "annotation"
          "resource.customizations.health.argoproj.io_Application" = <<-EOF
            hs = {}
            hs.status = "Progressing"
            hs.message = ""
            if obj.status ~= nil then
              if obj.status.health ~= nil then
                hs.status = obj.status.health.status
                if obj.status.health.message ~= nil then
                  hs.message = obj.status.health.message
                end
              end
            end
            return hs
          EOF
        }
      }
      repoServer = {
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
      }
      applicationSet = {
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "200m", memory = "256Mi" }
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd,
    terraform_data.argocd_images,
  ]
}

# App-of-Apps Bootstrap
# Uses the argocd-apps Helm chart to deploy the root Application resource.
# Helm manages the Application manifest, so terraform plan does not need the
# Argo CD CRD registered ahead of time (unlike kubernetes_manifest).

resource "helm_release" "argocd_apps" {
  name             = "argocd-apps"
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argocd-apps"
  version          = var.argocd_apps_chart_version
  cleanup_on_fail  = true
  create_namespace = false

  values = [
    yamlencode({
      applications = [
        {
          name       = "bootstrap"
          namespace  = kubernetes_namespace.argocd.metadata[0].name
          project    = "default"
          finalizers = ["resources-finalizer.argocd.argoproj.io"]
          source = {
            repoURL        = var.gitops_repo_url
            targetRevision = var.gitops_repo_target_revision
            path           = "gitops/bootstrap"
          }
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = kubernetes_namespace.argocd.metadata[0].name
          }
          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
            syncOptions = ["CreateNamespace=true"]
          }
        }
      ]
    })
  ]

  depends_on = [helm_release.argocd]
}
