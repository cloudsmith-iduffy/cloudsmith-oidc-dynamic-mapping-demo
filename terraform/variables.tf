variable "namespace" {
  description = "Cloudsmith organization slug that owns the OIDC config and service accounts."
  type        = string
  default     = "iduffy-demo"
}

variable "github_repository" {
  description = "owner/repo of the GitHub repository allowed to authenticate (matched against the OIDC 'repository' claim)."
  type        = string
  default     = "cloudsmith-iduffy/cloudsmith-oidc-dynamic-mapping-demo"
}

variable "github_issuer" {
  description = "GitHub Actions OIDC issuer URL."
  type        = string
  default     = "https://token.actions.githubusercontent.com"
}

variable "audience" {
  description = "Audience claim the OIDC token must carry."
  type        = string
  default     = "cloudsmith"
}
