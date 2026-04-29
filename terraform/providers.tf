terraform {
  required_version = ">= 1.5.0"
  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = ">= 5.7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0"
    }
    netbird = {
      source  = "netbirdio/netbird"
      version = ">= 0.0.9"
    }
  }
}

provider "keycloak" {
  client_id     = var.keycloak_client_id
  client_secret = var.keycloak_client_secret
  username      = var.keycloak_username
  password      = var.keycloak_password
  url           = var.keycloak_url
}

provider "netbird" {
  token          = var.netbird_token
  management_url = var.netbird_management_url
}