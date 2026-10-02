terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.80, < 7.0"
    }
  }

  # Backend is injected by the CI pipeline (see .github/workflows/deploy.yml)
  # when the repository variable TF_STATE_BUCKET is set. Otherwise state is local.
}

provider "aws" {
  region = var.region
}
