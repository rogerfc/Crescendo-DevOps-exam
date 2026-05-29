output "cloudfront_url" {
  description = "CloudFront URL to access Magnolia CMS"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "alb_dns_name" {
  description = "ALB DNS name (for debugging; not directly accessible from outside)"
  value       = aws_lb.main.dns_name
}
