output "client_proxy_ecr_image_digest" {
  value = length(data.aws_ecr_image.client_proxy_image) > 0 ? data.aws_ecr_image.client_proxy_image[0].image_digest : local.default_image_digest
}