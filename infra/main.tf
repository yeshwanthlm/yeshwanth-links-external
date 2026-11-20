# links.yeshwanthlm.in — socials page
#
#   private S3 bucket ─▶ CloudFront (OAC, HTTPS) ─▶ Route 53 alias in the existing yeshwanthlm.in zone
#
# Separate state from the main site (Yeshwanth-Website/infra), so applying this never touches it.
# Site files are uploaded by Terraform too (aws_s3_object), so state always matches what is live.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile
  default_tags {
    tags = { Project = "yeshwanthlm-socials", ManagedBy = "terraform" }
  }
}

provider "aws" {
  alias   = "us_east_1" # CloudFront only accepts ACM certificates from us-east-1
  region  = "us-east-1"
  profile = var.aws_profile
  default_tags {
    tags = { Project = "yeshwanthlm-socials", ManagedBy = "terraform" }
  }
}

data "aws_caller_identity" "me" {}

locals {
  fqdn     = "${var.subdomain}.${var.domain_name}"
  name     = "ylm-socials"
  bucket   = "${replace(local.fqdn, ".", "-")}-${data.aws_caller_identity.me.account_id}"
  site_dir = "${path.module}/../site"

  mime = {
    html = "text/html; charset=utf-8"
    css  = "text/css; charset=utf-8"
    js   = "text/javascript; charset=utf-8"
    png  = "image/png"
    svg  = "image/svg+xml"
    ico  = "image/x-icon"
    json = "application/json"
  }

  csp = join("; ", [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self' https://fonts.googleapis.com",
    "font-src https://fonts.gstatic.com",
    "img-src 'self' data:",
    "connect-src 'none'",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'none'",
    "object-src 'none'",
    "upgrade-insecure-requests",
  ])
}

# ───────────── DNS (existing zone, created with the domain) ─────────────
data "aws_route53_zone" "site" {
  name         = var.domain_name
  private_zone = false
}

# ───────────── TLS ─────────────
resource "aws_acm_certificate" "site" {
  provider          = aws.us_east_1
  domain_name       = local.fqdn
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}

resource "aws_route53_record" "cert_validation" {
  for_each = { for o in aws_acm_certificate.site.domain_validation_options : o.domain_name => o }
  zone_id  = data.aws_route53_zone.site.zone_id
  name     = each.value.resource_record_name
  type     = each.value.resource_record_type
  records  = [each.value.resource_record_value]
  ttl      = 300
}

resource "aws_acm_certificate_validation" "site" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ───────────── bucket (private; CloudFront is the only reader) ─────────────
resource "aws_s3_bucket" "site" {
  bucket = local.bucket
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid       = "CloudFrontReadOnly"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.site.arn, "${aws_s3_bucket.site.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket     = aws_s3_bucket.site.id
  policy     = data.aws_iam_policy_document.site_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.site]
}

# ───────────── site files ─────────────
resource "aws_s3_object" "site" {
  for_each      = fileset(local.site_dir, "**/*.{html,css,js,png,svg,ico,json}")
  bucket        = aws_s3_bucket.site.id
  key           = each.value
  source        = "${local.site_dir}/${each.value}"
  etag          = filemd5("${local.site_dir}/${each.value}")
  content_type  = lookup(local.mime, reverse(split(".", each.value))[0], "application/octet-stream")
  cache_control = endswith(each.value, ".html") ? "no-cache" : "public, max-age=300"
}

# ───────────── CloudFront ─────────────
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${local.name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_response_headers_policy" "site" {
  name = "${local.name}-security-headers"
  security_headers_config {
    content_security_policy {
      content_security_policy = local.csp
      override                = true
    }
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      override                   = true
    }
    content_type_options { override = true }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  comment             = local.fqdn
  aliases             = [local.fqdn]
  default_root_object = "index.html"
  price_class         = "PriceClass_200" # includes India edge locations

  origin {
    origin_id                = "s3"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = "s3"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id
  }

  # one-page site: any unknown path shows the links page
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# ───────────── DNS records ─────────────
resource "aws_route53_record" "site" {
  for_each = toset(["A", "AAAA"])
  zone_id  = data.aws_route53_zone.site.zone_id
  name     = local.fqdn
  type     = each.value
  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}
