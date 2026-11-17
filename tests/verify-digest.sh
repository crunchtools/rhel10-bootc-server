#!/usr/bin/env bash
# The signature boundary of disk.yml (install/verify-digest.sh): a malformed
# digest and an unsigned one are refused, a signed one passes. 1.2.0 predates
# signing (#44), so it stays unsigned for good.
set -euo pipefail
repo=quay.io/crunchtools/rhel10-bootc-server
key=etc/pki/sigstore/crunchtools-bootc.pub
check=install/verify-digest.sh
refuse() {
    if "$check" "$repo" "$1" "$key" >/dev/null 2>&1; then
        echo "::error::accepted a digest it must refuse ($2): '$1'" >&2; exit 1
    fi
    echo "refused as expected: $2"
}
refuse "" "empty"
refuse "latest" "a tag"
refuse "sha256:abc" "short digest"
refuse "sha256:$(printf 'A%.0s' {1..64})" "uppercase hex"
unsigned=$(skopeo inspect --no-tags --format '{{.Digest}}' "docker://$repo:1.2.0")
refuse "$unsigned" "unsigned 1.2.0"
signed=$(skopeo inspect --no-tags --format '{{.Digest}}' "docker://$repo:latest")
"$check" "$repo" "$signed" "$key"
echo "accepted the signed :latest"
