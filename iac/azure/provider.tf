provider "azurerm" {
  subscription_id = var.azure-subscription-id
  features {}
}
provider "azuread" {}

provider "auth0" {
  domain        = var.auth0_domain
  client_id     = var.auth0_client_id
  client_secret = var.auth0_client_secret
}

terraform {
  required_version = "= 1.13.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.30.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.4.0"
    }
    auth0 = {
      source  = "auth0/auth0"
      version = "= 1.33.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7.0"
    }
  }
}
