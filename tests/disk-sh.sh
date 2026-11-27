#!/usr/bin/env bash
# scripts/disk.sh's preconditions and orchestration, offline: a throwaway
# origin and clone, with id, sudo, curl and podman faked on PATH and the digest
# gate stubbed. Proves it refuses a non-root run before fetching anything, a
# dirty tree, a commit origin/main lacks, and a v* tag origin does not have;
# that a cosign whose sha256 is wrong stops it before the gate; and that a good
# run gates with the fetched cosign, builds from REPO@DIGEST, and can run twice
# into one outdir. The privileged build itself is not run: podman is faked.
set -euo pipefail

src=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fails=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fails=$((fails + 1)); }
digest=sha256:$(printf 'a%.0s' $(seq 64))
cosign_bytes='fake cosign v2.6.5'
cosign_sum=$(printf '%s' "$cosign_bytes" | sha256sum | cut -d' ' -f1)

# Fakes: id, sudo, curl, podman, gzip; curl and podman log their argv to $t/log.
mkdir -p "$t/bin"
cat > "$t/bin/id" <<EOF
#!/bin/sh
echo "\${FAKE_UID:-0}"
EOF
cat > "$t/bin/sudo" <<'EOF'
#!/bin/sh
shift 2   # -u <user>
exec "$@"
EOF
cat > "$t/bin/curl" <<EOF
#!/bin/sh
echo "curl \$*" >> "$t/log"
out=; while [ \$# -gt 0 ]; do [ "\$1" = -fsSLo ] && { out=\$2; shift; }; shift; done
printf '%s' "\${FAKE_COSIGN:-$cosign_bytes}" > "\$out"
EOF
cat > "$t/bin/podman" <<EOF
#!/bin/sh
echo "podman \$*" >> "$t/log"
[ "\$1" = run ] || exit 0
for a in "\$@"; do case \$a in *:/output) mkdir -p "\${a%:/output}/image"; echo raw > "\${a%:/output}/image/disk.raw" ;; esac; done
EOF
# gzip -1f <file>: the gate image has no gzip, and compression is not under test.
cat > "$t/bin/gzip" <<'EOF'
#!/bin/sh
cat "$2" > "$2.gz" && rm -f "$2"
EOF
chmod +x "$t/bin/"*

# The repo: what disk.sh reads, the gate stubbed, the cosign hash set to the fake's.
git init -q --bare -b main "$t/origin.git"
git clone -q "$t/origin.git" "$t/repo" 2>/dev/null
cd "$t/repo"
mkdir -p scripts tests install etc/pki/sigstore
sed "s/^COSIGN_SHA256=.*/COSIGN_SHA256=$cosign_sum/" "$src/scripts/disk.sh" > scripts/disk.sh
cat > tests/digest-gate.sh <<EOF
#!/bin/sh
echo "gate \$* cosign=\$(command -v cosign)" >> "$t/log"
echo "\$1@\$2"
EOF
chmod +x scripts/disk.sh tests/digest-gate.sh
echo 'ssh-ed25519 AAAA test' > install/root-authorized-keys
echo key > etc/pki/sigstore/crunchtools-bootc.pub
g() { git -c user.name=t -c user.email=t@invalid "$@"; }
g add -A && g commit -qm base && g push -q origin main

disk() {  # disk [env...]: run disk.sh, set rc and out
    : > "$t/log"; rc=0
    out=$(env PATH="$t/bin:$PATH" "$@" scripts/disk.sh "$digest" "$t/out" 2>&1) || rc=$?
}

disk FAKE_UID=1000
if [ "$rc" -ne 0 ] && grep -q 'run as root' <<< "$out" && ! [ -s "$t/log" ]; then
    ok "non-root is refused before anything is fetched"
else bad "non-root: rc=$rc $out"; fi

touch stray
disk
if [ "$rc" -ne 0 ] && grep -q 'not clean' <<< "$out"; then ok "a dirty tree is refused"
else bad "dirty tree: rc=$rc $out"; fi
rm stray

g commit -q --allow-empty -m local
disk
if [ "$rc" -ne 0 ] && grep -q 'neither on origin/main' <<< "$out"; then ok "a commit origin/main lacks is refused"
else bad "unpushed commit: rc=$rc $out"; fi

g tag v9.9.9
disk
if [ "$rc" -ne 0 ] && grep -q 'neither on origin/main' <<< "$out"; then ok "a v* tag only this clone has is refused"
else bad "local tag: rc=$rc $out"; fi

g push -q origin v9.9.9
disk FAKE_COSIGN=tampered
if [ "$rc" -ne 0 ] && grep -q '^curl ' "$t/log" && ! grep -q '^gate ' "$t/log"; then
    ok "a tag origin has at HEAD passes; a cosign with the wrong sha256 stops it before the gate"
else bad "bad cosign hash: rc=$rc $out"; fi

for run in first second; do
    disk
    if [ "$rc" -eq 0 ] && grep -q "^gate quay.io/crunchtools/rhel10-bootc-server $digest .*/bin/cosign\$" "$t/log" \
       && grep -q "^podman pull quay.io/crunchtools/rhel10-bootc-server@$digest\$" "$t/log" \
       && grep -q "build --type raw --rootfs xfs quay.io/crunchtools/rhel10-bootc-server@$digest\$" "$t/log" \
       && [ "$(cat "$t/out/image/SOURCE")" = "quay.io/crunchtools/rhel10-bootc-server@$digest" ] \
       && (cd "$t/out/image" && sha256sum -c --quiet SHA256SUM); then
        ok "$run good run: gated with the fetched cosign, built from REPO@DIGEST, SOURCE and SHA256SUM written"
    else bad "$run good run: rc=$rc $out"; cat "$t/log"; fi
done

git checkout -q HEAD~1   # base: on origin/main, no tag
disk
if [ "$rc" -eq 0 ] && grep -q '^gate ' "$t/log"; then ok "a commit on origin/main passes without a tag"
else bad "origin/main commit: rc=$rc $out"; fi

if [ "$fails" -ne 0 ]; then echo "disk.sh test FAILED: $fails"; exit 1; fi
echo "disk.sh test PASSED"
