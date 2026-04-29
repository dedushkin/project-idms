terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://hel1.your-objectstorage.com"
    }
    bucket                      = "idms-terraform-state"
    key                         = "idms/terraform.tfstate"
    region                      = "eu-central"
    profile                     = "idms"
    encrypt                     = false
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
  }
}