terraform {
  required_version = ">= 1.5.0"

  required_providers {
    cloudsmith = {
      source  = "cloudsmith-io/cloudsmith"
      version = "~> 0.0.79"
    }
  }
}

# api_key is read from the CLOUDSMITH_API_KEY environment variable.
provider "cloudsmith" {}
