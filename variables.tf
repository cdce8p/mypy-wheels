variable "aws_region" {
  description = "AWS region for all resources."

  type    = string
  default = "eu-central-1"
}

variable "repo" {
  description = "Full Github repo name OWNER/REPO ot trigger the GH action in."

  type    = string
  default = "cdce8p/mypy-wheels"
}

variable "github_pat" {
  description = "Github PAT with access to the repo to run the GH action in."

  type      = string
  sensitive = true
}

variable "sig_key" {
  description = "Secret key to validate webhook payload."

  type      = string
  sensitive = true
}

variable "mail_source" {
  description = "Source Email address, must be verified!"

  type        = string
  sensitive   = true
}

variable "mail_recipient" {
  description = "Recipient Email address."

  type        = string
  sensitive   = true
}
