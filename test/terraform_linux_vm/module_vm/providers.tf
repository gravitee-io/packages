terraform {
  required_version = ">=1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.94"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "02ae5fba-84b0-443a-9df6-9be92297c139" // Gravitee-SaaS
}
