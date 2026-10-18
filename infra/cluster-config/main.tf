data "azurerm_kubernetes_cluster" "platform" {
  name                = var.aks_cluster_name
  resource_group_name = var.aks_resource_group_name
}

# ─── Argo CD Namespace ────────────────────────────────────────────────────────

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# ─── Argo CD Installation ─────────────────────────────────────────────────────
# Installed from the official Helm chart. The app-of-apps pattern (in
# gitops/bootstrap/) bootstraps all downstream applications once Argo CD is up.

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
          # RBAC: require Entra ID group membership (configure dex separately)
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

  depends_on = [kubernetes_namespace.argocd]
}

# ─── App-of-Apps Bootstrap ────────────────────────────────────────────────────
# Creates a single root Argo CD Application that discovers all child
# Applications in gitops/bootstrap/.

resource "kubernetes_manifest" "app_of_apps" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "bootstrap"
      namespace  = kubernetes_namespace.argocd.metadata[0].name
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
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
  }

  depends_on = [helm_release.argocd]
}
