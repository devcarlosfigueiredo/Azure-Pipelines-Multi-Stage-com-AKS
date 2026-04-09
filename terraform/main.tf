# =============================================================================
# Azure DevOps Demo — Terraform Infrastructure
# Provisions: AKS + ACR + Key Vault + supporting resources
# =============================================================================

terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.50"
    }
  }

  # Remote state — Azure Storage Backend
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstatedemo"
    container_name       = "tfstate"
    key                  = "azure-devops-demo.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# ── Data Sources ──────────────────────────────────────────────────────────────
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# ── Resource Group ────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location

  tags = local.common_tags
}

# ── Local values ──────────────────────────────────────────────────────────────
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
    CostCenter  = var.cost_center
  }

  # Resource name prefixes per Azure naming convention
  acr_name   = "acr${replace(var.project_name, "-", "")}${var.environment}"
  kv_name    = "kv-${var.project_name}-${var.environment}"
  aks_name   = "aks-${var.project_name}-${var.environment}"
  law_name   = "law-${var.project_name}-${var.environment}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Azure Container Registry (ACR)
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_container_registry" "acr" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku
  admin_enabled       = false  # Use service principal, not admin credentials

  georeplications {
    location                = var.acr_geo_replication_location
    zone_redundancy_enabled = true
    tags                    = local.common_tags
  }

  # Vulnerability scanning (Defender for Containers)
  retention_policy {
    days    = var.acr_retention_days
    enabled = true
  }

  trust_policy {
    enabled = false  # Enable Content Trust in production
  }

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Log Analytics Workspace (monitoring foundation)
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_log_analytics_workspace" "law" {
  name                = local.law_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Azure Kubernetes Service (AKS)
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_kubernetes_cluster" "aks" {
  name                = local.aks_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  dns_prefix          = "${var.project_name}-${var.environment}"
  kubernetes_version  = var.kubernetes_version

  # System node pool
  default_node_pool {
    name                        = "system"
    node_count                  = var.system_node_count
    vm_size                     = var.system_node_vm_size
    os_disk_size_gb             = 128
    os_disk_type                = "Managed"
    type                        = "VirtualMachineScaleSets"
    enable_auto_scaling         = true
    min_count                   = 1
    max_count                   = var.system_node_max_count
    only_critical_addons_enabled = true  # Taint: system workloads only
    zones                       = ["1", "2", "3"]
    node_labels = {
      "nodepool-type" = "system"
      "environment"   = var.environment
    }
    tags = local.common_tags
  }

  # Managed Identity (recommended over service principal)
  identity {
    type = "SystemAssigned"
  }

  # RBAC + Azure AD integration
  azure_active_directory_role_based_access_control {
    managed                = true
    azure_rbac_enabled     = true
    admin_group_object_ids = var.aks_admin_group_object_ids
  }

  # Networking
  network_profile {
    network_plugin     = "azure"
    network_policy     = "calico"
    load_balancer_sku  = "standard"
    outbound_type      = "loadBalancer"
    service_cidr       = "10.0.0.0/16"
    dns_service_ip     = "10.0.0.10"
  }

  # Monitoring
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  }

  # Security
  azure_policy_enabled             = true
  local_account_disabled           = true  # Force AAD auth
  http_application_routing_enabled = false

  # Automatic upgrades
  automatic_channel_upgrade   = "patch"
  maintenance_window {
    allowed {
      day   = "Sunday"
      hours = [0, 1, 2]
    }
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,
      kubernetes_version,
    ]
  }
}

# ── User node pool (application workloads) ────────────────────────────────────
resource "azurerm_kubernetes_cluster_node_pool" "app" {
  name                  = "app"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.app_node_vm_size
  node_count            = var.app_node_count
  enable_auto_scaling   = true
  min_count             = var.app_node_min_count
  max_count             = var.app_node_max_count
  os_disk_size_gb       = 128
  zones                 = ["1", "2", "3"]

  node_labels = {
    "nodepool-type" = "app"
    "environment"   = var.environment
  }

  node_taints = []  # Accept all workloads

  tags = local.common_tags
}

# ── Grant AKS pull access to ACR ─────────────────────────────────────────────
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

# ─────────────────────────────────────────────────────────────────────────────
# Azure Key Vault
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_key_vault" "kv" {
  name                        = local.kv_name
  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  soft_delete_retention_days  = 90
  purge_protection_enabled    = true
  enable_rbac_authorization   = true  # RBAC instead of access policies

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = var.key_vault_allowed_ips
    virtual_network_subnet_ids = []
  }

  tags = local.common_tags
}

# ── Grant Terraform SP access to Key Vault ────────────────────────────────────
resource "azurerm_role_assignment" "kv_terraform_admin" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ── Grant AKS access to Key Vault secrets ────────────────────────────────────
resource "azurerm_role_assignment" "kv_aks_secrets" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

# ── Sample secrets (values managed outside Terraform) ────────────────────────
resource "azurerm_key_vault_secret" "app_db_connection" {
  name         = "app-db-connection-string"
  value        = "REPLACE_ME_VIA_PIPELINE"
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.kv_terraform_admin]

  lifecycle {
    ignore_changes = [value]  # Pipeline manages the actual value
  }
}

resource "azurerm_key_vault_secret" "app_secret_key" {
  name         = "app-secret-key"
  value        = "REPLACE_ME_VIA_PIPELINE"
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.kv_terraform_admin]

  lifecycle {
    ignore_changes = [value]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Diagnostic Settings — forward AKS logs to Log Analytics
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_monitor_diagnostic_setting" "aks_diagnostics" {
  name                       = "aks-diagnostics"
  target_resource_id         = azurerm_kubernetes_cluster.aks.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log { category = "kube-apiserver" }
  enabled_log { category = "kube-controller-manager" }
  enabled_log { category = "kube-scheduler" }
  enabled_log { category = "kube-audit" }
  enabled_log { category = "cluster-autoscaler" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "acr_diagnostics" {
  name                       = "acr-diagnostics"
  target_resource_id         = azurerm_container_registry.acr.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log { category = "ContainerRegistryRepositoryEvents" }
  enabled_log { category = "ContainerRegistryLoginEvents" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
