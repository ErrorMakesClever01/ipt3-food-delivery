# ─────────────────────────────────────────────────────────────────────────────
# versions.tf — provider + backend config
# Region: ap-south-1 (Mumbai)
# ─────────────────────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }

  # ── Recommended: store state in S3 + lock with DynamoDB ──────────────────
  # Uncomment after creating the S3 bucket and DynamoDB table manually:
  #
  # backend "s3" {
  #   bucket         = "techstore-tfstate-ap-south-1"
  #   key            = "prod/terraform.tfstate"
  #   region         = "ap-south-1"
  #   encrypt        = true
  #   dynamodb_table = "techstore-tfstate-lock"
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "tech-store"
      ManagedBy   = "terraform"
      Environment = "production"
      Region      = "ap-south-1"
    }
  }
}
