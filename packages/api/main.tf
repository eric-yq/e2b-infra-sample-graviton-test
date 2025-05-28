terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "5.34.0"
    }
  }
}

# Create ECR repository for custom environments
resource "aws_ecr_repository" "custom_environments_repository" {
  name                 = "${var.prefix}custom-environments"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

locals {
  # Set a default digest for first-time deployment
  default_image_digest = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
}

# Make this data source optional since the image may not exist yet during first deployment
data "aws_ecr_image" "api_image" {
  count           = 0 # Skip this data source until images are uploaded
  repository_name = var.ecr_repository_name
  image_tag       = "latest"
}

# Create AWS Secrets Manager secret for postgres connection string
resource "aws_secretsmanager_secret" "postgres_connection_string" {
  name        = "${var.prefix}-postgres-connection-string-2"
  description = "PostgreSQL connection string for the API"
  tags        = var.tags
}

# Create AWS Secrets Manager secret for posthog API key
resource "aws_secretsmanager_secret" "posthog_api_key" {
  name        = "${var.prefix}-posthog-api-key-2"
  description = "PostHog API key for analytics"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "posthog_api_key" {
  secret_id     = aws_secretsmanager_secret.posthog_api_key.id
  secret_string = " "

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Generate random password for API secret
resource "random_password" "api_secret" {
  length  = 32
  special = false
}

# Create AWS Secrets Manager secret for API secret
resource "aws_secretsmanager_secret" "api_secret" {
  name        = "${var.prefix}-api-secret-2"
  description = "Secret for the API service"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "api_secret_value" {
  secret_id     = aws_secretsmanager_secret.api_secret.id
  secret_string = random_password.api_secret.result
}

# Generate random password for API admin token
resource "random_password" "api_admin_secret" {
  length  = 32
  special = true
}

# Create AWS Secrets Manager secret for API admin token
resource "aws_secretsmanager_secret" "api_admin_token" {
  name        = "${var.prefix}-api-admin-token-2"
  description = "Admin token for the API service"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "api_admin_token_value" {
  secret_id     = aws_secretsmanager_secret.api_admin_token.id
  secret_string = random_password.api_admin_secret.result
}
