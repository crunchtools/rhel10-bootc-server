"""The shipped public key is an ECDSA P-256 key (#44).

Moved from container.yml's `signing key` job, which ran openssl. The gate image
has Python, not necessarily openssl, so this reads the PEM's DER directly: a
P-256 SubjectPublicKeyInfo is 91 bytes, names id-ecPublicKey and prime256v1,
and ends in an uncompressed point (0x04 then 64 bytes).
"""

import base64
import sys

PUB = "etc/pki/sigstore/crunchtools-bootc.pub"
EC_PUBLIC_KEY = bytes.fromhex("06072a8648ce3d0201")  # 1.2.840.10045.2.1
PRIME256V1 = bytes.fromhex("06082a8648ce3d030107")  # 1.2.840.10045.3.1.7

text = open(PUB).read()
try:
    body = text.split("-----BEGIN PUBLIC KEY-----")[1].split("-----END PUBLIC KEY-----")[0]
    der = base64.b64decode("".join(body.split()), validate=True)
except (IndexError, ValueError):
    der = b""
ok = len(der) == 91 and EC_PUBLIC_KEY in der[:30] and PRIME256V1 in der[:30] and der[-65] == 4
if not ok:
    print(f"{PUB} is not an ECDSA P-256 public key", file=sys.stderr)
    sys.exit(1)
print(f"{PUB}: ECDSA P-256")
