variable "region" {
  description = "AWS region for the bucket."
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "AWS CLI profile (same one the main site uses)."
  type        = string
  default     = "personal"
}

variable "domain_name" {
  description = "Apex domain. Its Route 53 zone must already exist."
  type        = string
  default     = "yeshwanthlm.in"
}

variable "subdomain" {
  description = "Subdomain for this page: <subdomain>.<domain_name>."
  type        = string
  default     = "links"
}
