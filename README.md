# Cloudsmith OIDC dynamic mapping demo

This repo authenticates GitHub Actions to Cloudsmith with no stored API key, using OpenID
Connect (OIDC). It also shows how Cloudsmith dynamic mapping routes one OIDC config to
different service accounts based on a single claim.

The payloads below are real, copied from a run of the demo workflow. Read top to bottom to
follow how a GitHub token becomes a Cloudsmith token.

Think of it like a passport. GitHub is a passport office. For each workflow run it issues a
short-lived passport (a token) stamped with who you are and where you came from: repo, branch,
environment. The passport carries a seal only GitHub can produce. Cloudsmith is a border guard
that trusts that office. It checks the seal is genuine, that the passport has not expired, and
that it is stamped for entry here, then decides what you are allowed to do. No shared password
ever changes hands.

## 1. The problem OIDC solves

Most CI setups authenticate with a long-lived API key stored as a secret. It never expires,
anyone who can read the secret can use it, and rotating it across a fleet of repos is a chore
nobody volunteers for.

OIDC removes the stored secret. GitHub mints a short-lived token for each workflow run that
describes exactly which repo, branch, and environment produced it. CI hands that token to
Cloudsmith. Cloudsmith verifies GitHub's signature and the claims, and returns a Cloudsmith
token when they match a config you set up ahead of time. Nothing long-lived is stored.

## 2. The problem OIDC with dynamic mapping solves

Plain OIDC ties a provider config to a fixed set of service accounts: non-human identities in
Cloudsmith, each with its own permissions. Every distinct identity, each repository,
environment, or branch that needs its own permissions, needs its own provider config. With a handful of repos that is fine. With a hundred, you are creating and maintaining a
hundred near-identical configs, and every new repo is another one to add.

Dynamic mapping collapses that to one config. You pick a claim to route on, list which claim
values map to which service account, and a single provider serves every identity. Adding a repo
or environment is one new mapping entry, not a new provider.

## 3. The decoded GitHub token

The token is a JWT (JSON Web Token): the passport from above, written as text in three
base64url parts: header, payload, and signature. Here are the header and payload of a token
from a run in the `production` environment.

Header:

```json
{
  "alg": "RS256",
  "kid": "38826b17-6a30-5f9b-b169-8beb8202f723",
  "typ": "JWT",
  "x5t": "ykNaY4qM_ta4k2TgZOCEYLkcYlA"
}
```

Payload:

```json
{
  "actor": "cloudsmith-iduffy",
  "aud": "cloudsmith",
  "environment": "production",
  "event_name": "push",
  "iat": 1781179925,
  "exp": 1781180225,
  "iss": "https://token.actions.githubusercontent.com",
  "job_workflow_ref": "cloudsmith-iduffy/cloudsmith-oidc-dynamic-mapping-demo/.github/workflows/demo.yml@refs/heads/main",
  "ref": "refs/heads/main",
  "repository": "cloudsmith-iduffy/cloudsmith-oidc-dynamic-mapping-demo",
  "repository_owner": "cloudsmith-iduffy",
  "repository_visibility": "public",
  "run_id": "27345841282",
  "sub": "repo:cloudsmith-iduffy/cloudsmith-oidc-dynamic-mapping-demo:environment:production",
  "workflow": "demo"
}
```

Each field is a claim: a fact GitHub asserts about this run. `iat` and `exp` are 300 seconds
apart, so the token expires five minutes after GitHub issues it. The signature, which is not
shown, is what lets a verifier prove GitHub really issued these claims.

## 4. The issuer

The `iss` claim names who minted the token: `https://token.actions.githubusercontent.com`.
Cloudsmith trusts a token only when its `iss` matches the `provider_url` you configured. Find
the issuer's keys and you can verify anything it signed, so the issuer is the root of trust.

## 5. Discovery with .well-known/openid-configuration

The issuer publishes how to verify its tokens at a fixed path:

```bash
curl -s https://token.actions.githubusercontent.com/.well-known/openid-configuration | jq .
```

The real response includes:

```json
{
  "issuer": "https://token.actions.githubusercontent.com",
  "jwks_uri": "https://token.actions.githubusercontent.com/.well-known/jwks",
  "id_token_signing_alg_values_supported": ["RS256"]
}
```

`jwks_uri` points at the signing keys. `RS256` is the signing algorithm, which matches the
`alg` in the header from section 3.

## 6. JWKS, the issuer's public keys

```bash
jwks_uri=$(curl -s https://token.actions.githubusercontent.com/.well-known/openid-configuration | jq -r .jwks_uri)
curl -s "$jwks_uri" | jq .
```

The response is a set of public keys, each with a key id (`kid`). GitHub signs each token with
one private key and records that key's `kid` in the token header. The header in section 3 has
`kid: 38826b17-6a30-5f9b-b169-8beb8202f723`, and that exact key is in the live set:

```json
{
  "kid": "38826b17-6a30-5f9b-b169-8beb8202f723",
  "kty": "RSA",
  "alg": "RS256",
  "use": "sig",
  "n": "5Manmy-zwsk3wEftXNdKFZec…(truncated)"
}
```

A verifier reads the `kid` from the header, fetches the matching public key, and checks the
signature with it. The signature works like the passport's seal: GitHub creates it with a
private key only it holds, anyone can verify it with the matching public key, and nobody else
can reproduce it. Cloudsmith caches the key set, so it does not refetch on every request.

## 7. How Cloudsmith validates the token

Cloudsmith checks, in order:

1. Signature: GitHub's private key signed the token, verified with the JWKS public key for that
   `kid`. Change one byte of the payload and this fails.
2. Expiry: `iat` and `exp` put the token inside its five-minute window.
3. Issuer: `iss` matches the configured `provider_url`.
4. Audience: `aud` names who the token is for, and matches the configured audience,
   `cloudsmith`.

Any failure rejects the exchange.

## 8. Claim assertions

Signature and the standard claims are not enough. Cloudsmith also requires the claims you
configure. This demo requires:

```hcl
claims = {
  aud        = "cloudsmith"
  repository = "cloudsmith-iduffy/cloudsmith-oidc-dynamic-mapping-demo"
}
```

So only this repository authenticates. Claim values take a `.*` wildcard, for example
`repo:owner/name:.*`, which is how you widen or narrow the set of workflows you trust.

## 9. The Cloudsmith configuration

On the Cloudsmith side you create one or more OIDC providers and the service accounts each
provider can authenticate as. This demo has three service accounts (`demo-static`, `demo-prod`,
`demo-staging`), one static provider, and one dynamic provider. You can see them under
Settings → OpenID Connect in the org.

## 10. Static mapping

```hcl
resource "cloudsmith_oidc" "static" {
  provider_url     = "https://token.actions.githubusercontent.com"
  service_accounts = [cloudsmith_service.demo_static.slug]
  claims           = { aud = "cloudsmith", repository = "cloudsmith-iduffy/cloudsmith-oidc-dynamic-mapping-demo" }
}
```

A static provider maps to a fixed service account. Any token that matches the claims
authenticates as `demo-static`. This is the per-identity provider that section 2 described:
one config, one identity.

## 11. Dynamic mapping

```hcl
resource "cloudsmith_oidc" "dynamic" {
  provider_url  = "https://token.actions.githubusercontent.com"
  mapping_claim = "environment"          # the claim Cloudsmith routes on
  dynamic_mappings {
    claim_value     = "production"
    service_account = cloudsmith_service.demo_prod.slug
  }
  dynamic_mappings {
    claim_value     = "staging"
    service_account = cloudsmith_service.demo_staging.slug
  }
  claims = { aud = "cloudsmith", repository = "cloudsmith-iduffy/cloudsmith-oidc-dynamic-mapping-demo" }
}
```

One provider routes on the value of the `environment` claim:

| `environment` claim | Authenticates as |
|---|---|
| `production` | `demo-prod` |
| `staging` | `demo-staging` |

A token from the `production` environment exchanges for a Cloudsmith token:

```json
{
  "alg": "HS256",
  "typ": "JWT"
}
```
```json
{
  "iat": 1781179926,
  "exp": 1781187126,
  "service_slug": "demo-prod",
  "service_slug_perm": "GfL2xLz6zN3H"
}
```

And `GET /v1/user/self/` confirms the identity:

```json
{
  "authenticated": true,
  "name": "demo-prod",
  "slug": "demo-prod",
  "slug_perm": "GfL2xLz6zN3H",
  "self_url": "https://api.cloudsmith.io/v1/user/self/"
}
```

The same config, exercised from the `staging` environment, authenticates as `demo-staging`
instead. The identity is decided by the `environment` claim.

### The security gate

A request still names the service account it wants, and the token's claim value has to map to
that exact account. A token from the `staging` environment that asks for `demo-prod` is
rejected with a 401:

```json
{
  "detail": "Failed to validate token"
}
```

`staging` maps to `demo-staging`, so a staging workflow cannot get a production identity.
