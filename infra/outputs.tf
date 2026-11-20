output "url" {
  value = "https://${local.fqdn}"
}

output "distribution_id" {
  description = "For cache refresh after a change: aws cloudfront create-invalidation --distribution-id <id> --paths '/*'"
  value       = aws_cloudfront_distribution.site.id
}
