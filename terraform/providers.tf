terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.20"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # State lives locally by default so the repo clones and plans with no setup.
  # For anything shared, switch to a remote backend with locking:
  #
  # backend "s3" {
  #   bucket         = "mcztm-tfstate"
  #   key            = "landing-zone/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "mcztm-tfstate-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

provider "azurerm" {
  subscription_id = var.azure_subscription_id
  tenant_id       = var.entra_tenant_id

  features {
    resource_group {
      # Refuse to delete a resource group that still holds resources Terraform
      # does not know about.
      prevent_deletion_if_contains_resources = true
    }
  }
}

provider "azuread" {
  tenant_id = var.entra_tenant_id
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}
