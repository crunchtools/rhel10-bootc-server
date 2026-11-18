#!/usr/bin/env bash
# The signature boundary of disk.yml.
#
#   digest-gate.sh REPO DIGEST PUBKEY   prints REPO@DIGEST when DIGEST is a
#                                       sha256 digest PUBKEY signed; fails
#                                       otherwise. disk.yml builds nothing
#                                       from a digest this refuses.
#   digest-gate.sh                      self-test: a malformed digest and an
#                                       unsigned one are refused, a signed one
#                                       passes. 1.2.0 predates signing (#44),
#                                       so it stays unsigned for good.
set -euo pipefail

gate() {
    local repo=$1 digest=$2 key=$3
    [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] \
        || { echo "::error::not a sha256 digest: '$digest'" >&2; return 1; }
    cosign verify --insecure-ignore-tlog --key "$key" "$repo@$digest" >/dev/null \
        || { echo "::error::$repo@$digest is not signed by $key" >&2; return 1; }
    echo "$repo@$digest"
}

if [ $# -gt 0 ]; then
    gate "$@"
    exit
fi

repo=quay.io/crunchtools/rhel10-bootc-server
key=etc/pki/sigstore/crunchtools-bootc.pub
refuse() {
    if gate "$repo" "$1" "$key" >/dev/null 2>&1; then
        echo "::error::accepted a digest it must refuse ($2): '$1'" >&2; exit 1
    fi
    echo "refused as expected: $2"
}
refuse "" "empty"
refuse "latest" "a tag"
refuse "sha256:abc" "short digest"
refuse "sha256:$(printf 'A%.0s' {1..64})" "uppercase hex"
refuse "$(skopeo inspect --no-tags --format '{{.Digest}}' "docker://$repo:1.2.0")" "unsigned 1.2.0"
gate "$repo" "$(skopeo inspect --no-tags --format '{{.Digest}}' "docker://$repo:latest")" "$key"
echo "accepted the signed :latest"
