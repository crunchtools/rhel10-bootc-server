"""The shipped public key is a valid ECDSA P-256 key (#44).

Hosts verify every pull against it, so a key that cannot be used must fail here.
The gate image has Python, not necessarily openssl or a crypto library, so this
validates the PEM itself, stdlib only:

- the DER is exactly a P-256 SubjectPublicKeyInfo: the fixed 26-byte header
  (SEQUENCE, AlgorithmIdentifier id-ecPublicKey + prime256v1, BIT STRING with
  no unused bits) followed by an uncompressed point, 0x04 then X and Y;
- X and Y are field elements and the point lies on the curve
  y^2 = x^3 - 3x + b (mod p), which also rules out the point at infinity.

Before judging the shipped key it judges known-bad variants of it (wrong
header, wrong curve, compressed or truncated point, a point off the curve,
broken base64, missing or wrong PEM lines), so a check that accepts anything
fails instead of passing.
"""

import base64
import re
import sys

PUB = "etc/pki/sigstore/crunchtools-bootc.pub"

# SEQUENCE(89) { SEQUENCE(19) { OID id-ecPublicKey, OID prime256v1 }, BIT STRING(66), padding 0 }
SPKI_P256 = bytes.fromhex("3059301306072a8648ce3d020106082a8648ce3d030107034200")
COORD = 32  # bytes in a P-256 field element
UNCOMPRESSED = 0x04  # SEC 1 point-format prefix
POINT = 1 + 2 * COORD  # uncompressed: the prefix, X, Y
P = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
B = 0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
PEM = re.compile(r"-----BEGIN PUBLIC KEY-----\n([A-Za-z0-9+/=\n]+)-----END PUBLIC KEY-----\n?")


def der_of(text: str) -> bytes:
    """The DER of a file holding exactly one PEM public key, or b"" for anything else."""
    m = PEM.fullmatch(text)
    if not m:
        return b""
    try:
        return base64.b64decode(m.group(1).replace("\n", ""), validate=True)
    except ValueError:
        return b""


def is_p256(der: bytes) -> bool:
    if len(der) != len(SPKI_P256) + POINT or not der.startswith(SPKI_P256):
        return False
    point = der[len(SPKI_P256):]
    if point[0] != UNCOMPRESSED:
        return False
    x = int.from_bytes(point[1 : 1 + COORD], "big")
    y = int.from_bytes(point[1 + COORD :], "big")
    if x >= P or y >= P:
        return False
    return (y * y - (x * x * x - 3 * x + B)) % P == 0


def pem(der: bytes) -> str:
    b64 = base64.b64encode(der).decode()
    return f"-----BEGIN PUBLIC KEY-----\n{b64}\n-----END PUBLIC KEY-----\n"


def main() -> int:
    with open(PUB) as f:
        text = f.read()
    der = der_of(text)
    if not is_p256(der):
        print(f"{PUB} is not a valid ECDSA P-256 public key", file=sys.stderr)
        return 1

    h = len(SPKI_P256)
    bad = {
        "wrong algorithm OID": der[:12] + b"\x00" + der[13:],
        "wrong curve OID": der[:22] + b"\x08" + der[23:],
        "nonzero unused bits": der[: h - 1] + b"\x01" + der[h:],
        "compressed point": der[:h] + b"\x02" + der[h + 1 :],
        "truncated point": der[:-1],
        "point off the curve": der[:-1] + bytes([der[-1] ^ 1]),
        "coordinate not a field element": der[: h + 1] + b"\xff" * COORD + der[h + 1 + COORD :],
    }
    wrong = [name for name, d in bad.items() if is_p256(der_of(pem(d)))]
    bad_pem = {
        "broken base64": text.replace("KEY-----\n", "KEY-----\n!", 1),
        "no BEGIN line": text.replace("-----BEGIN PUBLIC KEY-----\n", ""),
        "no END line": text.replace("-----END PUBLIC KEY-----", ""),
        "a private-key label": text.replace("PUBLIC KEY", "PRIVATE KEY"),
        "text after the key": text + "trailing\n",
    }
    wrong += [name for name, t in bad_pem.items() if is_p256(der_of(t))]
    if wrong:
        print(f"the P-256 check accepts what it must refuse: {', '.join(wrong)}", file=sys.stderr)
        return 1
    refused = len(bad) + len(bad_pem)
    print(f"{PUB}: ECDSA P-256, point on the curve; {refused} malformed variants refused")
    return 0


if __name__ == "__main__":
    sys.exit(main())
