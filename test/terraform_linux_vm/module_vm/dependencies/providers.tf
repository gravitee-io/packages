terraform {
  required_version = ">=1.7"

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~>1.12.1"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.94"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.6"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "02ae5fba-84b0-443a-9df6-9be92297c139" // Gravitee-SaaS
}
