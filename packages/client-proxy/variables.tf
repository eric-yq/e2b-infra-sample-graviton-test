variable "aws_account_id" {
  description = "The AWS account ID to deploy the cluster in"
  type        = string
}

variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
}

variable "ecr_repository_name" {
  description = "The ECR repository name for orchestration"
  type        = string
}