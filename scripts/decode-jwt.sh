#!/usr/bin/env bash
# Decode a JWT's header and payload (NOT verifying the signature) and pretty-print as JSON.
# Usage: decode-jwt.sh <jwt>
set -euo pipefail
token="${1:?usage: decode-jwt.sh <jwt>}"

python3 - "$token" <<'PY'
import sys, json, base64

def decode_segment(segment):
    padded = segment + "=" * (-len(segment) % 4)
    return json.loads(base64.urlsafe_b64decode(padded.encode()))

token = sys.argv[1].strip()
parts = token.split(".")
if len(parts) < 2:
    sys.exit("not a JWT (expected at least header.payload)")

print("── header ──")
print(json.dumps(decode_segment(parts[0]), indent=2, sort_keys=True))
print("── payload ──")
print(json.dumps(decode_segment(parts[1]), indent=2, sort_keys=True))
PY
