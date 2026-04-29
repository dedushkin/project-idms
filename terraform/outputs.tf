output "netbird_client_id" {
  value = keycloak_openid_client.netbird.client_id
}

output "netbird_client_secret" {
  value     = keycloak_openid_client.netbird.client_secret
  sensitive = true
}

output "netbird_initial_username" {
  value = keycloak_user.netbird_initial_user.username
}

output "netbird_initial_password" {
  description = "The generated password for netbird initial user"
  value       = random_password.netbird_initial_pass.result
  sensitive   = true
}

output "grafana_client_id" {
  description = "The Client ID for Grafana"
  value       = keycloak_openid_client.grafana.client_id
}

output "grafana_client_secret" {
  description = "The Client Secret for Grafana"
  value       = keycloak_openid_client.grafana.client_secret
  sensitive   = true
}

output "oidc_issuer" {
  description = "The OpenID Connect Issuer URL"
  value       = "${var.keycloak_url}/realms/${keycloak_realm.my_realm.realm}"
}

output "midpoint_username" {
  value = keycloak_user.midpoint.username
}

output "midpoint_password" {
  description = "The generated password for midpoint user"
  value       = random_password.midpoint_pass.result
  sensitive   = true
}

output "midpoint_client_id" {
  description = "The Client ID for Midpoint"
  value       = keycloak_openid_client.midpoint.client_id
}

output "midpoint_client_secret" {
  description = "The Client Secret for Midpoint"
  value       = keycloak_openid_client.midpoint.client_secret
  sensitive   = true
}

output "gitlab_client_id" {
  description = "The Client ID for Gitlab"
  value       = keycloak_openid_client.gitlab.client_id
}

output "gitlab_client_secret" {
  description = "The Client Secret for Gitlab"
  value       = keycloak_openid_client.gitlab.client_secret
  sensitive   = true
}