resource "cloudsmith_service" "demo_static" {
  name         = "demo-static"
  organization = var.namespace
  description  = "Static OIDC mapping target (the 'old way': one provider, one service account)."
}

resource "cloudsmith_service" "demo_prod" {
  name         = "demo-prod"
  organization = var.namespace
  description  = "Dynamic OIDC mapping target for environment=production."
}

resource "cloudsmith_service" "demo_staging" {
  name         = "demo-staging"
  organization = var.namespace
  description  = "Dynamic OIDC mapping target for environment=staging."
}

# Static provider: any token matching the claims may authenticate as demo-static.
resource "cloudsmith_oidc" "static" {
  namespace        = var.namespace
  name             = "demo-static-provider"
  enabled          = true
  provider_url     = var.github_issuer
  service_accounts = [cloudsmith_service.demo_static.slug]

  claims = {
    aud        = var.audience
    repository = var.github_repository
  }
}

# Dynamic provider: the 'environment' claim value routes to a specific service account.
resource "cloudsmith_oidc" "dynamic" {
  namespace     = var.namespace
  name          = "demo-dynamic-provider"
  enabled       = true
  provider_url  = var.github_issuer
  mapping_claim = "environment"

  dynamic_mappings {
    claim_value     = "production"
    service_account = cloudsmith_service.demo_prod.slug
  }

  dynamic_mappings {
    claim_value     = "staging"
    service_account = cloudsmith_service.demo_staging.slug
  }

  claims = {
    aud        = var.audience
    repository = var.github_repository
  }
}
