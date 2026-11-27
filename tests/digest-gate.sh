#!/usr/bin/env bash
# The signature boundary of scripts/disk.sh.
#
#   digest-gate.sh REPO DIGEST PUBKEY   prints REPO@DIGEST when DIGEST is a
#                                       sha256 digest PUBKEY signed; fails
#                                       otherwise. disk.sh builds nothing
#                                       from a digest this refuses.
#   digest-gate.sh                      self-test: a malformed digest and an
#                                       unsigned one are refused, a signed one
#                                       passes. Offline (#76): the images live
#                                       in tests/oci-registry.py on loopback,
#                                       signed by a key made for the run.
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

work=$(mktemp -d)
python3 tests/oci-registry.py "$work/port" &
registry=$!
trap 'kill "$registry" 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 50); do [ -s "$work/port" ] && break; sleep 0.1; done
[ -s "$work/port" ] || { echo "::error::the fixture registry did not start" >&2; exit 1; }

repo=127.0.0.1:$(cat "$work/port")/rhel10-bootc-server
key=$work/cosign.pub
export COSIGN_PASSWORD=
(cd "$work" && cosign generate-key-pair >/dev/null 2>&1)
digest_of() {
    skopeo inspect --tls-verify=false --no-tags --format '{{.Digest}}' "docker://$repo:$1"
}
signed=$(digest_of signed)
cosign sign --yes --tlog-upload=false --use-signing-config=false --new-bundle-format=false --key "$work/cosign.key" "$repo@$signed" >/dev/null 2>&1 \
    || { echo "::error::could not sign the fixture image" >&2; exit 1; }

refuse() {
    if gate "$repo" "$1" "${3:-$key}" >/dev/null 2>&1; then
        echo "::error::accepted a digest it must refuse ($2): '$1'" >&2; exit 1
    fi
    echo "refused as expected: $2"
}
refuse "" "empty"
refuse "latest" "a tag"
refuse "sha256:abc" "short digest"
refuse "sha256:$(printf 'A%.0s' {1..64})" "uppercase hex"
refuse "$(digest_of unsigned)" "unsigned image"
refuse "$signed" "signed by another key" etc/pki/sigstore/crunchtools-bootc.pub
gate "$repo" "$signed" "$key" >/dev/null
echo "accepted the signed image"
