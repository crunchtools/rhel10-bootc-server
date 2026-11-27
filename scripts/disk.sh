#!/usr/bin/env bash
# Raw disk for hosts that cannot install from the registry (RT#1638): what
# disk.yml did, run by hand (a1790). Linode boots a raw disk with direct-disk,
# and `bootc install to-existing-root` fails there because Linode disks carry no
# partition table; a bootc-image-builder raw written onto a raw Linode disk is
# the route that works (hosts/lotor/README.md).
#
#   sudo scripts/disk.sh sha256:<digest> [outdir]
#
# Needs real root: osbuild refuses rootless podman, and the fleet ci.yml runs no
# privileged job, so this is an operator's command on a host such as Dolza.
# The source digest must carry the bootc signature (tests/digest-gate.sh), or
# nothing is built: a disk is a host, and it should start from what a host
# would accept as an update. The root key comes from this checkout's
# install/root-authorized-keys, so only a clean main or v* tag builds: any other
# tree could ship someone else's key. The disk boots pinned to that digest;
# after first boot, `bootc switch` to :latest, which the shipped policy verifies.
set -euo pipefail

REPO=quay.io/crunchtools/rhel10-bootc-server
# cosign v2, checked by hash, as disk.yml installed it: v3 stores signatures as
# OCI referrers, which c/image cannot read.
COSIGN_URL=https://github.com/sigstore/cosign/releases/download/v2.6.5/cosign-linux-amd64
COSIGN_SHA256=c3b4f5410e608af03a5eb0aaac84a4313d8da131248e08ff1759ac70c79d1644
# Pinned by digest: the builder runs privileged.
BIB=quay.io/centos-bootc/bootc-image-builder@sha256:dab86ee6b46dcade411b37f4e70b07d93b6a06da0dbfec6fe89247a220e0d9f8

digest=${1:?usage: scripts/disk.sh sha256:<digest> [outdir]}
cd "$(git rev-parse --show-toplevel)"
out=$(realpath -m "${2:-output}")

[ "$(id -u)" = 0 ] || { echo "run as root: osbuild needs real root, not rootless podman" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "the tree is not clean" >&2; exit 1; }
git fetch -q origin main --tags
if ! git merge-base --is-ancestor HEAD origin/main && ! git describe --exact-match --match 'v*' HEAD >/dev/null 2>&1; then
    echo "HEAD is neither on origin/main nor a v* tag" >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
curl -fsSLo "$work/bin/cosign" "$COSIGN_URL"
echo "$COSIGN_SHA256  $work/bin/cosign" | sha256sum -c --quiet
chmod 0755 "$work/bin/cosign"
image=$(PATH="$work/bin:$PATH" tests/digest-gate.sh "$REPO" "$digest" etc/pki/sigstore/crunchtools-bootc.pub)

# Quay drops a blob mid-read now and then on an image this size.
for try in 1 2 3; do
    podman pull "$image" && break
    [ "$try" = 3 ] && exit 1
    sleep 20
done

key=$(grep -m1 '^ssh-' install/root-authorized-keys)
printf '[[customizations.user]]\nname = "root"\nkey = "%s"\n' "$key" > "$work/config.toml"
mkdir -p "$out"
podman run --rm --privileged --pull=missing --security-opt label=type:unconfined_t \
    -v "$work/config.toml:/config.toml:ro" -v "$out:/output" \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    "$BIB" build --type raw --rootfs xfs "$image"
gzip -1f "$out/image/disk.raw"
cd "$out/image"
echo "$image" > SOURCE
sha256sum disk.raw.gz | tee SHA256SUM
