# =============================================================================
# Variables — Azure DevOps Demo Infrastructure
# =============================================================================

# ── Project ───────────────────────────────────────────────────────────────────
variable "project_name" {
  description = "Project name used as prefix for all Azure resources."
  type        = string
  default     = "azdevops-demo"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric with hyphens, 3–24 chars."
  }
}

variable "environment" {
  description = "Deployment environment: staging | production."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be 'staging' or 'production'."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "West Europe"
}

variable "owner" {
  description = "Team or individual responsible for this environment."
  type        = string
  default     = "platform-engineering"
}

variable "cost_center" {
  description = "Cost centre tag for billing attribution."
  type        = string
  default     = "engineering"
}

# ── ACR ───────────────────────────────────────────────────────────────────────
variable "acr_sku" {
  description = "ACR pricing tier: Basic | Standard | Premium."
  type        = string
  default     = "Premium"  # Premium required for geo-replication & Private Link

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "acr_sku must be Basic, Standard, or Premium."
  }
}

variable "acr_geo_replication_location" {
  description = "Secondary region for ACR geo-replication (Premium tier only)."
  type        = string
  default     = "North Europe"
}

variable "acr_retention_days" {
  description = "Days to retain untagged manifests before purging."
  type        = number
  default     = 30
}

# ── AKS ───────────────────────────────────────────────────────────────────────
variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster."
  type        = string
  default     = "1.30"
}

variable "aks_admin_group_object_ids" {
  description = "Azure AD group object IDs granted cluster-admin role."
  type        = list(string)
  default     = []
}

# System node pool
variable "system_node_count" {
  description = "Initial node count for the system node pool."
  type        = number
  default     = 2
}

variable "system_node_vm_size" {
  description = "VM size for system node pool nodes."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "system_node_max_count" {
  description = "Maximum nodes for system pool auto-scaler."
  type        = number
  default     = 4
}

# App node pool
variable "app_node_vm_size" {
  description = "VM size for application node pool nodes."
  type        = string
  default     = "Standard_D4s_v3"
}

variable "app_node_count" {
  description = "Initial node count for the app node pool."
  type        = number
  default     = 2
}

variable "app_node_min_count" {
  description = "Minimum nodes for app pool auto-scaler."
  type        = number
  default     = 1
}

variable "app_node_max_count" {
  description = "Maximum nodes for app pool auto-scaler."
  type        = number
  default     = 10
}

# ── Monitoring ────────────────────────────────────────────────────────────────
variable "log_retention_days" {
  description = "Days to retain logs in Log Analytics Workspace."
  type        = number
  default     = 90
}

# ── Key Vault ─────────────────────────────────────────────────────────────────
variable "key_vault_allowed_ips" {
  description = "IP ranges allowed to access Key Vault (pipeline agent IPs)."
  type        = list(string)
  default     = []
}
