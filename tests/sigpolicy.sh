#!/bin/bash
# Build-time test: the shipped signature policy makes every quay.io/crunchtools
# image need the bootc key (#47).
#
#   sigpolicy.sh POLICY REGISTRIES_D   checks the files as shipped
#   sigpolicy.sh                       self-test: a correct pair passes, and a
#                                      shadowing scope, a wrong identity or a
#                                      missing sigstore namespace each fail.
#
# c/image applies the most specific scope, so one quay.io/crunchtools/<repo>
# entry (in policy.json or registries.d) quietly exempts that repository from
# the namespace rule. The generator in the Containerfile checks what it adds;
# this checks the result it has to produce.
set -euo pipefail

KEY=/etc/pki/sigstore/crunchtools-bootc.pub

check() {
    python3 -I - "$1" "$2" "$KEY" <<'PY'
import json, os, sys
policy_path, regd, key = sys.argv[1:]
with open(policy_path) as f:
    docker = json.load(f).get("transports", {}).get("docker", {})
want = [{"type": "sigstoreSigned", "keyPath": key,
         "signedIdentity": {"type": "matchRepository"}}]
assert docker.get("quay.io/crunchtools") == want, docker.get("quay.io/crunchtools")
extra = [s for s in docker if s.startswith("quay.io/crunchtools/")]
assert not extra, "scopes shadow the namespace rule: %s" % extra
ns, shadow = False, []
for name in sorted(os.listdir(regd)):
    if not name.endswith((".yaml", ".yml")):
        continue
    lines = [l.strip() for l in open(os.path.join(regd, name))]
    for i, line in enumerate(lines):
        if line == "quay.io/crunchtools:":
            ns = ns or "use-sigstore-attachments: true" in lines[i + 1:i + 3]
        elif line.startswith("quay.io/crunchtools/"):
            shadow.append(name + ": " + line)
assert ns, "no registries.d entry turns on sigstore attachments for quay.io/crunchtools"
assert not shadow, "registries.d entries shadow the namespace: %s" % shadow
PY
}

if [ $# -gt 0 ]; then
    check "$@"
    exit
fi

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/regd" "$W/bad"
good='{"default":[{"type":"insecureAcceptAnything"}],"transports":{"docker":{"quay.io/crunchtools":[{"type":"sigstoreSigned","keyPath":"'$KEY'","signedIdentity":{"type":"matchRepository"}}]}}}'
echo "$good" > "$W/good.json"
printf 'docker:\n  quay.io/crunchtools:\n    use-sigstore-attachments: true\n' > "$W/regd/a.yaml"
check "$W/good.json" "$W/regd" || { echo "FAIL: a correct policy was refused" >&2; exit 1; }

refuse() {
    if check "$1" "$2" 2>/dev/null; then
        echo "FAIL: accepted $3" >&2
        exit 1
    fi
}
python3 -I -c 'import json,sys; p=json.loads(sys.argv[1]); p["transports"]["docker"]["quay.io/crunchtools/x"]=[{"type":"insecureAcceptAnything"}]; print(json.dumps(p))' "$good" > "$W/shadow.json"
refuse "$W/shadow.json" "$W/regd" "a shadowing policy scope"
sed 's/matchRepository/matchExact/' "$W/good.json" > "$W/exact.json"
refuse "$W/exact.json" "$W/regd" "a matchExact identity"
printf 'docker:\n  quay.io/crunchtools/x:\n    use-sigstore-attachments: false\n' > "$W/regd/b.yaml"
refuse "$W/good.json" "$W/regd" "a shadowing registries.d entry"
refuse "$W/good.json" "$W/bad" "no sigstore namespace"
echo "sigpolicy: self-test passed"
