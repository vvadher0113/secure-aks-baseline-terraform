output "argocd_namespace" {
  description = "Kubernetes namespace where Argo CD is installed."
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_server_service" {
  description = "Port-forward command to access the Argo CD UI locally."
  value       = "kubectl port-forward svc/argocd-server -n ${kubernetes_namespace.argocd.metadata[0].name} 8080:443"
}
