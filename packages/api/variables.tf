variable "prefix" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "iam_role_arn" {
  type = string
}

variable "ecr_repository_name" {
  type = string
}

variable "tags" {
  description = "The tags to attach to AWS resources created by this module"
  type        = map(string)
}