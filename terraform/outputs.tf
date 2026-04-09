# =============================================================================
# Outputs — referenced by Azure Pipelines variable groups
# =============================================================================

output "resource_group_name" {
  description = "Resource group containing all project resources."
  value       = azurerm_resource_group.main.name
}

output "acr_login_server" {
  description = "ACR login server URL (used in docker push / Helm values)."
  value       = azurerm_container_registry.acr.login_server
}

output "acr_name" {
  description = "ACR resource name."
  value       = azurerm_container_registry.acr.name
}

output "aks_cluster_name" {
  description = "AKS cluster name (used in kubectl / Helm commands)."
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_cluster_fqdn" {
  description = "AKS API server FQDN."
  value       = azurerm_kubernetes_cluster.aks.fqdn
  sensitive   = true
}

output "aks_kubeconfig" {
  description = "Raw kubeconfig — store in Key Vault, never in pipelines."
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity federation."
  value       = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "key_vault_name" {
  description = "Key Vault name."
  value       = azurerm_key_vault.kv.name
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = azurerm_key_vault.kv.vault_uri
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for Grafana / dashboards."
  value       = azurerm_log_analytics_workspace.law.workspace_id
}
