output "service_slugs" {
  description = "Service account slugs to use as service_slug in the token exchange."
  value = {
    static  = cloudsmith_service.demo_static.slug
    prod    = cloudsmith_service.demo_prod.slug
    staging = cloudsmith_service.demo_staging.slug
  }
}

output "oidc_static_slug_perm" {
  description = "Permanent slug of the static OIDC provider config."
  value       = cloudsmith_oidc.static.slug_perm
}

output "oidc_dynamic_slug_perm" {
  description = "Permanent slug of the dynamic OIDC provider config."
  value       = cloudsmith_oidc.dynamic.slug_perm
}
