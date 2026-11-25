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
SDLC_KEY=/etc/pki/sigstore/crunchtools-sdlc.pub

check() {
    python3 -I - "$1" "$2" "$KEY" "$SDLC_KEY" <<'PY'
import json, os, sys
policy_path, regd, key, sdlc_key = sys.argv[1:]
with open(policy_path) as f:
    docker = json.load(f).get("transports", {}).get("docker", {})
want = [{"type": "sigstoreSigned", "keyPath": key,
         "signedIdentity": {"type": "matchRepository"}}]
assert docker.get("quay.io/crunchtools") == want, docker.get("quay.io/crunchtools")
# sdlc's two repositories take sdlc's key as well; nothing else may differ.
sdlc = [{"type": "sigstoreSigned", "keyPaths": [sdlc_key, key],
         "signedIdentity": {"type": "matchRepository"}}]
for repo in ("sdlc", "sdlc-bootstrap"):
    assert docker.get("quay.io/crunchtools/" + repo) == sdlc, docker.get("quay.io/crunchtools/" + repo)
extra = [s for s in docker if s.startswith("quay.io/crunchtools/")
         and s not in ("quay.io/crunchtools/sdlc", "quay.io/crunchtools/sdlc-bootstrap")]
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
good=$(python3 -I -c 'import json,sys; k,sk=sys.argv[1:]
ns=[{"type":"sigstoreSigned","keyPath":k,"signedIdentity":{"type":"matchRepository"}}]
sd=[{"type":"sigstoreSigned","keyPaths":[sk,k],"signedIdentity":{"type":"matchRepository"}}]
d={"quay.io/crunchtools":ns,"quay.io/crunchtools/sdlc":sd,"quay.io/crunchtools/sdlc-bootstrap":sd}
print(json.dumps({"default":[{"type":"insecureAcceptAnything"}],"transports":{"docker":d}}))' "$KEY" "$SDLC_KEY")
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
python3 -I -c 'import json,sys; p=json.loads(sys.argv[1]); p["transports"]["docker"]["quay.io/crunchtools/sdlc"]=[{"type":"insecureAcceptAnything"}]; print(json.dumps(p))' "$good" > "$W/sdlc-open.json"
refuse "$W/sdlc-open.json" "$W/regd" "an sdlc scope that accepts anything"
sed 's/matchRepository/matchExact/' "$W/good.json" > "$W/exact.json"
refuse "$W/exact.json" "$W/regd" "a matchExact identity"
printf 'docker:\n  quay.io/crunchtools/x:\n    use-sigstore-attachments: false\n' > "$W/regd/b.yaml"
refuse "$W/good.json" "$W/regd" "a shadowing registries.d entry"
refuse "$W/good.json" "$W/bad" "no sigstore namespace"
echo "sigpolicy: self-test passed"
