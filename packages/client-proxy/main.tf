terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.34.0"
    }
  }
}

locals {
  # Set a default digest for first-time deployment
  default_image_digest = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
}

# Make this data source optional since the image may not exist yet during first deployment
data "aws_ecr_image" "client_proxy_image" {
  count           = 0 # Skip this data source until images are uploaded
  repository_name = var.ecr_repository_name
  image_tag       = "client-proxy"
}
