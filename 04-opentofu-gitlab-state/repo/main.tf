terraform {
  required_version = ">= 1.12"

  # GitLab-managed state: the pipeline's gitlab-tofu fills in the address
  # and the credentials (the job token) from CI variables.
  backend "http" {}
}

variable "environment" {
  type    = string
  default = "lab"
}

# terraform_data is built into OpenTofu, so this needs no provider download.
resource "terraform_data" "release" {
  input = {
    environment = var.environment
    version     = "1.0.0"
  }
}

output "release" {
  value = terraform_data.release.output
}
