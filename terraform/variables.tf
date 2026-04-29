variable "domain_name" {
  description = "The domain name for subdomains"
  type        = string
  default     = "example.com"
}

variable "keycloak_smtp_config" {
  description = "SMTP configuration for Keycloak email settings"
  type = object({
    host     = string,
    port     = number,
    from     = string,
    ssl      = bool,
    username = string,
    password = string,
  })
}

variable "keycloak_client_id" {
  description = "The client ID of the Keycloak admin CLI"
  type        = string
  default     = "admin-cli"
}

variable "keycloak_client_secret" {
  description = "The client secret for the admin-cli (if required)"
  type        = string
  default     = null
  sensitive   = true
}

variable "keycloak_username" {
  description = "The username for the Keycloak admin user"
  type        = string
  default     = null
}

variable "keycloak_password" {
  description = "The password for the Keycloak admin user"
  type        = string
  default     = null
  sensitive   = true
}

variable "keycloak_url" {
  description = "The URL of the Keycloak server"
  type        = string
  default     = "https://keycloak.example.com"
}

variable "realm_name" {
  description = "The name of the Keycloak realm to create"
  type        = string
  default     = "example"
}

variable "realm_display_name" {
  description = "The display name for the Keycloak realm"
  type        = string
  default     = "Example Realm"
}

variable "netbird_token" {
  description = "The API token for Netbird"
  type        = string
  sensitive   = true
}

variable "netbird_management_url" {
  description = "The management URL for Netbird"
  type        = string
}

variable "netbird_initial_email" {
  description = "The email address for the Netbird initial SSO user"
  type        = string
}

variable "netbird_group_list" {
  description = "List of Netbird groups to create"
  type        = list(string)
  default     = ["internal-users", "k8s-api-users"]
}

variable "kubernetes_gateway_service_fqdn" {
  description = "The FQDN of the Kubernetes gateway service for DNS configuration"
  type        = string
}

variable "grafana_url" {
  description = "The URL of the Grafana instance"
  type        = string
}

variable "midpoint_url" {
  description = "The URL of the Midpoint instance"
  type        = string
}

variable "gitlab_url" {
  description = "The URL of the Gitlab instance"
  type        = string
}