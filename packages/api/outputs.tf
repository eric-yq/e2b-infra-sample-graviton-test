output "api_ecr_image_digest" {
  value = length(data.aws_ecr_image.api_image) > 0 ? data.aws_ecr_image.api_image[0].image_digest : local.default_image_digest
}

output "api_secret_arn" {
  value = aws_secretsmanager_secret.api_secret.arn
}

output "rds_connection_string_secret_name" {
  value = aws_secretsmanager_secret.postgres_connection_string.name
}

output "posthog_api_key_secret_name" {
  value = aws_secretsmanager_secret.posthog_api_key.name
}

output "custom_envs_ecr_repository_name" {
  value = aws_ecr_repository.custom_environments_repository.name
}

output "api_admin_token_arn" {
  value = aws_secretsmanager_secret.api_admin_token.arn
}