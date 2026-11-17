#!/usr/bin/env bash
# Usage: verify-digest.sh REPO DIGEST PUBKEY
# Prints REPO@DIGEST when DIGEST is a sha256 digest that PUBKEY signed, and
# fails otherwise. disk.yml builds nothing from a digest this refuses.
set -euo pipefail
repo=$1 digest=$2 key=$3
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] \
    || { echo "::error::not a sha256 digest: '$digest'" >&2; exit 1; }
cosign verify --insecure-ignore-tlog --key "$key" "$repo@$digest" >/dev/null \
    || { echo "::error::$repo@$digest is not signed by $key" >&2; exit 1; }
echo "$repo@$digest"
