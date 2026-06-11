# Cloudsmith OIDC Dynamic Mapping Demo

A live, end-to-end demonstration of how GitHub Actions authenticates to Cloudsmith
**without any long-lived API key**, using OpenID Connect (OIDC) — and how Cloudsmith's
**dynamic mapping** routes a single OIDC configuration to different service accounts based
on a claim in the token.

This README is the walkthrough. Read it top to bottom while looking at a run of the
[`demo` workflow](../../actions/workflows/demo.yml).

## 1. The problem OIDC solves

The old way: store a long-lived Cloudsmith API key as a CI secret. It never expires, it
can leak, and rotating it is painful.

The OIDC way: GitHub mints a **short-lived, signed token** describing *this specific
workflow run* (which repo, which branch, which environment). CI hands that token to
Cloudsmith. Cloudsmith verifies GitHub's signature and the claims, and — if they match a
configuration we set up in advance — returns a Cloudsmith token. No secret is ever stored.

## 2. The decoded GitHub token

Open the `static-whoami` job logs and find **"GitHub OIDC token (decoded)"**. A JWT is
three base64url parts: `header.payload.signature`. We only decode header + payload (the
signature is bytes, not JSON). Example payload:

```json
{
  "iss": "https://token.actions.githubusercontent.com",
  "aud": "cloudsmith",
  "sub": "repo:cloudsmith-iduffy/cloudsmith-oidc-dynamic-mapping-demo:ref:refs/heads/main",
  "repository": "cloudsmith-iduffy/cloudsmith-oidc-dynamic-mapping-demo",
  "environment": "production",
  "iat": 1700000000,
  "exp": 1700000900
}
```

These key/value pairs are **claims**. `iat`/`exp` make it short-lived (~15 min).

## 3. The issuer (`iss`)

The `iss` claim names who minted the token: `https://token.actions.githubusercontent.com`.
Cloudsmith only trusts tokens whose `iss` matches the `provider_url` we configured. The
issuer is the root of trust — everything else hangs off being able to find and verify
*that* issuer's keys.

## 4. `.well-known/openid-configuration`

Given the issuer URL, anyone can discover how to verify its tokens by fetching:

```
https://token.actions.githubusercontent.com/.well-known/openid-configuration
```

Try it:

```bash
curl -s https://token.actions.githubusercontent.com/.well-known/openid-configuration | jq .
```

The important field is `jwks_uri` — the URL of the issuer's public signing keys.

## 5. JWKS — the issuer's public keys

```bash
jwks_uri=$(curl -s https://token.actions.githubusercontent.com/.well-known/openid-configuration | jq -r .jwks_uri)
curl -s "$jwks_uri" | jq .
```

This **JWKS** (JSON Web Key Set) is a list of public keys, each with a key id (`kid`).
GitHub signs each token with one private key and puts its `kid` in the token **header**.
Cloudsmith reads the `kid` from the header, fetches the matching public key from the JWKS,
and uses it to verify the signature. (Cloudsmith caches the JWKS so it isn't fetched on
every request.)

## 6. Validation

To accept a token, Cloudsmith checks, in order:

1. **Signature** — the token was signed by the issuer's private key (verified with the
   JWKS public key for that `kid`). Tampering breaks this.
2. **`exp` / `iat`** — the token is currently valid (not expired).
3. **`iss`** — matches the configured `provider_url`.
4. **`aud`** — matches the configured audience (`cloudsmith`).

If any check fails, the exchange is rejected.

## 7. Claim assertions

Beyond signature and the standard claims, Cloudsmith requires the claims *we* configured to
be present and to match. In `terraform/main.tf` both providers assert:

```hcl
claims = {
  aud        = "cloudsmith"
  repository = "cloudsmith-iduffy/cloudsmith-oidc-dynamic-mapping-demo"
}
```

So only this repository can authenticate. Values support a `.*` wildcard (e.g.
`repo:owner/name:.*`). This is how you scope access down to exactly the workflows you trust.

## 8. The Cloudsmith configuration

Everything on the Cloudsmith side is Terraform in [`terraform/`](terraform/):

- 3 **service accounts**: `demo-static`, `demo-prod`, `demo-staging`.
- 1 **static** `cloudsmith_oidc` provider.
- 1 **dynamic** `cloudsmith_oidc` provider.

It is applied by the `provision` job of the [`demo` workflow](../../actions/workflows/demo.yml):
that job runs `terraform apply` and publishes the created service-account slugs as job
outputs, which the `static-whoami` / `dynamic-*` jobs receive as the `SERVICE_SLUG` env var —
so the slugs are never hardcoded, they flow straight from Terraform. (Terraform state is kept
in the Actions cache, so the apply is a no-op create on every run after the first.) You can
also see these resources under **Settings → OpenID Connect** in the `iduffy-demo` Cloudsmith
org.

## 9. Static mapping (the simple case)

```hcl
resource "cloudsmith_oidc" "static" {
  provider_url     = "https://token.actions.githubusercontent.com"
  service_accounts = [cloudsmith_service.demo_static.slug]
  claims           = { aud = "cloudsmith", repository = "cloudsmith-iduffy/cloudsmith-oidc-dynamic-mapping-demo" }
}
```

One provider → one (or a fixed list of) service account(s). Any token matching the claims
can act as `demo-static`. The `static-whoami` job proves this. If you have 50 repos that each
need their own identity, you end up maintaining 50 of these. That's the pain dynamic mapping
removes.

## 10. Dynamic mapping (the headline)

```hcl
resource "cloudsmith_oidc" "dynamic" {
  provider_url  = "https://token.actions.githubusercontent.com"
  mapping_claim = "environment"          # <-- look at THIS claim
  dynamic_mappings {
    claim_value     = "production"        # environment=production
    service_account = cloudsmith_service.demo_prod.slug
  }
  dynamic_mappings {
    claim_value     = "staging"           # environment=staging
    service_account = cloudsmith_service.demo_staging.slug
  }
  claims = { aud = "cloudsmith", repository = "cloudsmith-iduffy/cloudsmith-oidc-dynamic-mapping-demo" }
}
```

**One** configuration routes by the value of the `environment` claim:

| Job | `environment` claim | Authenticates as |
|---|---|---|
| `dynamic-production` | `production` | `demo-prod` |
| `dynamic-staging` | `staging` | `demo-staging` |

Compare the **whoami** output of those two jobs — same config, different identities,
decided entirely by the token's `environment` claim.

### The security gate

The caller still names the `service_slug` it wants, and the token's claim value must map to
*that exact* service account. The `negative-staging-asks-for-prod` job runs in `environment:
staging` but asks for `demo-prod` — and Cloudsmith **rejects** it, because `staging` maps to
`demo-staging`, not `demo-prod`. A staging workflow cannot mint a production identity.

### Scaling beyond one repo

Here we route on `environment` so a single repo can show it. In the real world you'd often
set `mapping_claim = "repository"` and add one `dynamic_mappings` entry per repo — one OIDC
provider config serving an entire org, each repository pinned to its own service account.

## Running it yourself

1. Set the `CLOUDSMITH_API_KEY` repo secret (a Cloudsmith service account key with Manager
   rights on `iduffy-demo`).
2. Push any commit (or run the **demo** workflow manually). The `provision` job creates the
   Cloudsmith config with Terraform and the downstream jobs do the token exchange and `whoami`.
3. Read the job logs — every JWT is decoded inline (header + payload; the signature is
   redacted).
