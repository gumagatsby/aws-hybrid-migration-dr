terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }

  # Bucket and region are passed at init time: see README "Deploying".
  backend "s3" {
    key          = "hybrid-migration-dr/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

locals {
  tags = { Project = "hybrid-migration-dr", ManagedBy = "terraform" }
}

provider "aws" {
  region = var.primary_region
  default_tags { tags = local.tags }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region
  default_tags { tags = local.tags }
}
