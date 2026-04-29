# === Keycloak ===

data "keycloak_realm" "master" {
  realm = "master"
}

resource "keycloak_realm" "my_realm" {
  realm                    = var.realm_name
  enabled                  = true
  display_name             = var.realm_display_name
  login_theme              = "keycloak"
  access_code_lifespan     = "1h"
  ssl_required             = "external"
  password_policy          = "upperCase(1) and length(8) and forceExpiredPasswordChange(365) and notUsername"
  reset_password_allowed   = true
  verify_email             = true
  login_with_email_allowed = true

  attributes = {
    frontendUrl = var.keycloak_url
  }

  smtp_server {
    host = var.keycloak_smtp_config.host
    port = var.keycloak_smtp_config.port
    from = var.keycloak_smtp_config.from
    ssl  = var.keycloak_smtp_config.ssl

    auth {
      username = var.keycloak_smtp_config.username
      password = var.keycloak_smtp_config.password
    }
  }

  otp_policy {
    type = "totp"
  }
}

resource "keycloak_required_action" "required_action_totp" {
  realm_id       = keycloak_realm.my_realm.id
  alias          = "CONFIGURE_TOTP"
  name           = "Configure OTP"
  enabled        = true
  default_action = true
}

resource "keycloak_required_action" "required_action_update_password" {
  realm_id       = keycloak_realm.my_realm.id
  alias          = "UPDATE_PASSWORD"
  name           = "Update Password"
  enabled        = true
  default_action = true
}

resource "keycloak_required_action" "required_action_verify_email" {
  realm_id       = keycloak_realm.my_realm.id
  alias          = "VERIFY_EMAIL"
  name           = "Verify Email"
  enabled        = true
  default_action = true
}

resource "keycloak_realm_events" "realm_events" {
  realm_id = keycloak_realm.my_realm.id

  events_enabled    = true
  events_expiration = 3600

  admin_events_enabled         = true
  admin_events_details_enabled = true

  events_listeners = ["jboss-logging"]
}


# === Netbird ===

# Создание клиента Netbird
resource "keycloak_openid_client" "netbird" {
  realm_id              = keycloak_realm.my_realm.id
  client_id             = "netbird"
  name                  = "Netbird"
  enabled               = true
  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true
  valid_redirect_uris   = ["${var.netbird_management_url}/oauth2/callback"]
}

# Создание маппера в Client Scope
resource "keycloak_openid_client_scope" "netbird_groups_client_scope" {
  realm_id               = keycloak_realm.my_realm.id
  name                   = "nbgroups"
  description            = "This scope will map a user's Netbird client roles to a claim netbird-groups"
  include_in_token_scope = true
}

resource "keycloak_openid_user_client_role_protocol_mapper" "netbird_client_roles" {
  realm_id                    = keycloak_realm.my_realm.id
  client_scope_id             = keycloak_openid_client_scope.netbird_groups_client_scope.id
  name                        = "groups"
  client_id_for_role_mappings = "netbird"
  multivalued                 = true
  claim_name                  = "groups"
  claim_value_type            = "String"
  add_to_id_token             = true
  add_to_access_token         = true
  add_to_userinfo             = true
}

resource "keycloak_openid_client_default_scopes" "netbird_default_scopes" {
  realm_id  = keycloak_realm.my_realm.id
  client_id = keycloak_openid_client.netbird.id

  default_scopes = [
    "profile",
    "basic",
    "email",
    keycloak_openid_client_scope.netbird_groups_client_scope.name
  ]
}

resource "keycloak_openid_client_optional_scopes" "netbird_optional_scopes" {
  realm_id  = keycloak_realm.my_realm.id
  client_id = keycloak_openid_client.netbird.id

  optional_scopes = [
    "address",
    "phone",
    "organization",
    "offline_access"
  ]
}

resource "keycloak_role" "netbird_roles" {
  for_each  = toset(var.netbird_group_list)
  realm_id  = keycloak_realm.my_realm.id
  client_id = keycloak_openid_client.netbird.id
  name      = each.key
}

# Создание тестового пользователя
# Под ним необходимо залогиниться один раз для создания необходимых ролей и групп

resource "random_password" "netbird_initial_pass" {
  length  = 18
  special = false
  upper   = true
  lower   = true
  numeric = true
}

resource "keycloak_user" "netbird_initial_user" {
  realm_id   = keycloak_realm.my_realm.id
  username   = "netbird-initial-user"
  enabled    = true
  email      = var.netbird_initial_email
  first_name = "Netbird"
  last_name  = "Initial User"
  initial_password {
    value     = random_password.netbird_initial_pass.result
    temporary = false
  }
}

resource "keycloak_user_roles" "netbird_initial_user_assignment" {
  realm_id = keycloak_realm.my_realm.id
  user_id  = keycloak_user.netbird_initial_user.id

  # Назначаем все роли
  role_ids = [for r in keycloak_role.netbird_roles : r.id]
}

# Настройка Netbird
resource "netbird_identity_provider" "keycloak_idp" {
  name          = "Keycloak"
  type          = "oidc"
  client_id     = keycloak_openid_client.netbird.client_id
  client_secret = keycloak_openid_client.netbird.client_secret
  issuer        = "${var.keycloak_url}/realms/${keycloak_realm.my_realm.realm}"
}

resource "netbird_account_settings" "my_netbird_settings" {
  peer_login_expiration                  = 7200
  peer_inactivity_expiration             = 7200
  peer_login_expiration_enabled          = true
  peer_inactivity_expiration_enabled     = true
  regular_users_view_blocked             = true
  groups_propagation_enabled             = true
  jwt_groups_enabled                     = true
  jwt_groups_claim_name                  = "groups"
  routing_peer_dns_resolution_enabled    = true
  peer_approval_enabled                  = false
  network_traffic_logs_enabled           = false
  network_traffic_packet_counter_enabled = false
  user_approval_required                 = false
}

data "netbird_group" "all" {
  name = "All"
}

# Группа для NB Routers
resource "netbird_group" "kubernetes" {
  name = "kubernetes"
}

# DNS
resource "netbird_nameserver_group" "example" {
  name    = "Public DNS"
  primary = true
  nameservers = [
    {
      ip      = "1.1.1.1"
      ns_type = "udp"
      port    = 53
    },
    {
      ip      = "8.8.8.8"
      ns_type = "udp"
      port    = 53
    }
  ]
  groups                 = [data.netbird_group.all.id]
  search_domains_enabled = false
}

resource "netbird_nameserver_group" "internal" {
  name    = "Kube-DNS"
  primary = false
  domains = ["svc.cluster.local"]
  nameservers = [
    {
      ip      = "10.96.0.10"
      ns_type = "udp"
      port    = 53
    }
  ]
  groups                 = [netbird_group.kubernetes.id]
  search_domains_enabled = false
}

resource "netbird_dns_zone" "internal" {
  name                 = "internal-zone"
  domain               = var.domain_name
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.all.id]
}

resource "netbird_dns_record" "gateway" {
  zone_id = netbird_dns_zone.internal.id
  name    = "*.${var.domain_name}"
  type    = "CNAME"
  content = var.kubernetes_gateway_service_fqdn
  ttl     = 60
}

# Отключаем дефолтную политику, так как она разрешает все соединения между всеми ресурсами, что не соответствует требованиям безопасности
data "netbird_policy" "default" {
  name = "Default"
}

import {
  to = netbird_policy.default
  id = data.netbird_policy.default.id
}

resource "netbird_policy" "default" {
  name    = data.netbird_policy.default.name
  enabled = false
  rule {
    action        = "accept"
    bidirectional = true
    description   = "This is a default rule that allows connections between all the resources"
    destinations  = [data.netbird_group.all.id]
    enabled       = false
    name          = "Default"
    protocol      = "all"
    sources       = [data.netbird_group.all.id]
  }
}

resource "netbird_policy" "allow_kubernetes_peer_connections" {
  name    = "Allow Kubernetes Peer Connections"
  enabled = true
  rule {
    action        = "accept"
    bidirectional = false
    description   = "This is a rule that allows connections to Kubernetes peers from all other resources"
    destinations  = [resource.netbird_group.kubernetes.id]
    enabled       = true
    name          = "Default"
    protocol      = "all"
    sources       = [data.netbird_group.all.id]
  }
}

# === Grafana ===

resource "keycloak_openid_client" "grafana" {
  realm_id                     = keycloak_realm.my_realm.id
  client_id                    = "grafana"
  name                         = "Grafana"
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = true
  root_url                     = var.grafana_url
  admin_url                    = var.grafana_url
  base_url                     = var.grafana_url
  valid_redirect_uris          = ["${var.grafana_url}/*"]
}

resource "keycloak_role" "grafana_roles" {
  for_each  = toset(["grafanaadmin", "admin", "editor", "viewer"])
  realm_id  = keycloak_realm.my_realm.id
  client_id = keycloak_openid_client.grafana.id
  name      = each.key
}

resource "keycloak_openid_client_default_scopes" "grafana_scopes" {
  realm_id  = keycloak_realm.my_realm.id
  client_id = keycloak_openid_client.grafana.id

  default_scopes = [
    "email",
    "profile",
    "roles",
    "offline_access"
  ]
}

resource "keycloak_openid_client_optional_scopes" "grafana_scopes" {
  realm_id  = keycloak_realm.my_realm.id
  client_id = keycloak_openid_client.grafana.id

  optional_scopes = []
}

resource "keycloak_openid_full_name_protocol_mapper" "grafana_full_name" {
  realm_id  = keycloak_realm.my_realm.id
  client_id = keycloak_openid_client.grafana.id
  name      = "full name"
}

resource "keycloak_openid_user_property_protocol_mapper" "grafana_email" {
  realm_id      = keycloak_realm.my_realm.id
  client_id     = keycloak_openid_client.grafana.id
  name          = "email"
  user_property = "email"
  claim_name    = "email"
}

resource "keycloak_openid_user_property_protocol_mapper" "grafana_username" {
  realm_id      = keycloak_realm.my_realm.id
  client_id     = keycloak_openid_client.grafana.id
  name          = "username"
  user_property = "username"
  claim_name    = "preferred_username"
}

resource "keycloak_openid_user_client_role_protocol_mapper" "grafana_client_roles" {
  realm_id  = keycloak_realm.my_realm.id
  client_id = keycloak_openid_client.grafana.id
  name      = "client roles"

  client_id_for_role_mappings = "grafana"
  claim_name                  = "roles"
  multivalued                 = true

  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# === Midpoint User (for Keycloak connector) ===

resource "random_password" "midpoint_pass" {
  length  = 18
  special = false
  upper   = true
  lower   = true
  numeric = true
}

resource "keycloak_user" "midpoint" {
  realm_id   = data.keycloak_realm.master.id
  username   = "midpoint"
  enabled    = true
  email      = "midpoint@${var.domain_name}"
  first_name = "Midpoint"
  last_name  = "Admin"

  initial_password {
    value     = random_password.midpoint_pass.result
    temporary = false
  }
}

data "keycloak_role" "realm_admin" {
  realm_id = data.keycloak_realm.master.id
  name     = "admin"
}

resource "keycloak_user_roles" "midpoint_admin_assignment" {
  realm_id = data.keycloak_realm.master.id
  user_id  = keycloak_user.midpoint.id

  role_ids = [
    data.keycloak_role.realm_admin.id
  ]
}

# === Midpoint Client (for SSO) ===

resource "keycloak_openid_client" "midpoint" {
  realm_id              = keycloak_realm.my_realm.id
  client_id             = "midpoint"
  name                  = "Midpoint"
  enabled               = true
  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true
  root_url              = var.midpoint_url
  admin_url             = var.midpoint_url
  base_url              = var.midpoint_url
  valid_redirect_uris   = ["${var.midpoint_url}/midpoint/*"]
}

# === Gitlab Client ===

resource "keycloak_openid_client" "gitlab" {
  realm_id              = keycloak_realm.my_realm.id
  client_id             = "gitlab"
  name                  = "Gitlab"
  enabled               = true
  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true
  root_url              = var.gitlab_url
  admin_url             = var.gitlab_url
  base_url              = var.gitlab_url
  valid_redirect_uris   = ["${var.gitlab_url}/users/auth/*"]
}