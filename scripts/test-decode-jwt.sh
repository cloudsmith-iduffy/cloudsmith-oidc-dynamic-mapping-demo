#!/usr/bin/env bash
# Test for decode-jwt.sh: builds a known unsigned JWT and asserts header+payload decode.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

b64url() { python3 -c 'import sys,base64;print(base64.urlsafe_b64encode(sys.stdin.buffer.read()).decode().rstrip("="))'; }
header="$(printf '%s' '{"alg":"RS256","kid":"test-key-id"}' | b64url)"
payload="$(printf '%s' '{"iss":"https://token.actions.githubusercontent.com","sub":"repo:owner/repo:environment:production","aud":"cloudsmith","environment":"production"}' | b64url)"
jwt="${header}.${payload}.c2lnbmF0dXJl"

out="$("${here}/decode-jwt.sh" "$jwt")"

fail=0
for needle in '"kid": "test-key-id"' '"iss": "https://token.actions.githubusercontent.com"' '"environment": "production"' '"aud": "cloudsmith"' '── header ──' '── payload ──'; do
  if ! grep -qF "$needle" <<<"$out"; then
    echo "MISSING: $needle"; fail=1
  fi
done

if [ "$fail" -ne 0 ]; then echo "FAIL"; echo "$out"; exit 1; fi
echo "PASS"
