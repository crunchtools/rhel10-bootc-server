# Signing key: rotation and loss

The bootc images are signed with one cosign key (#44). Hosts trust the public
half, `etc/pki/sigstore/crunchtools-bootc.pub` in this repository and in
rhel10-bootc-workstation. The private half and its password are the
`COSIGN_PRIVATE_KEY` and `COSIGN_PASSWORD` secrets of the `cosign-signing`
environment in both repositories. That environment deploys only from `main`
and `v*` tags, and no copy of the key belongs anywhere else.

Signing runs inside the constitution's `container-release.yml` (`sign: true`,
#47), which refuses a key that is not the private half of the constitution's
`keys/crunchtools-bootc.pub`. Rotating the key therefore also needs a
constitution release that ships the new public key, and both repositories must
pin that release before their secrets change. Until then every promotion fails
and no tag moves.

A host checks every update against the key it already has. A new key reaches
a host only in an image that host accepts, so the order below matters.

## Planned rotation (old key still available)

1. Generate the new pair: `cosign generate-key-pair --output-key-prefix crunchtools-bootc-next`.
2. Pull request in both repositories: ship the new public key beside the old
   one, and change the policy entries from `keyPath` to
   `"keyPaths": [old, new]`. Merge and release. The old key signs this image,
   so hosts accept it, and from then on they trust both keys.
3. Wait until every host has upgraded. On each one,
   `jq '.transports.docker' /etc/containers/policy.json` must show both keys.
4. Release the constitution with the new key in `keys/crunchtools-bootc.pub`.
   Then, in both repositories, replace the two secrets in the `cosign-signing`
   environment with the new pair and merge the pin bump to that release.
5. Pull request in both repositories: make the new key the only key (back to
   `keyPath`), and remove the old file. Merge and release. The new key signs
   this image, and hosts still trust it.
6. Destroy the old private key and password.

## Lost key (password or private key gone, nothing leaked)

Hosts keep running the image they have and refuse every update. Nothing is
exposed, but no update reaches a host until each one is given the new key by
hand.

1. Generate a new pair and release the constitution with the new public key
   in `keys/crunchtools-bootc.pub`. Put the pair in the `cosign-signing`
   environment of both repositories, then merge a pull request there that
   ships the new public key and pins that release. Its promotion is signed
   with the new key.
2. On each host, as root:
   `cp <new>.pub /etc/pki/sigstore/crunchtools-bootc.pub && bootc upgrade`.
3. After the reboot, the image ships the same file. `ostree admin config-diff`
   must not list it as modified, or later rotations will not reach this host.

## Compromised key (private key and password may be known to someone else)

Treat it as lost, and do it now. Anyone with the key and a Quay push token
can ship a host an image it accepts. Follow "Lost key", with two changes:
rotate the Quay robot token as well, and do step 2 on every host before its next
scheduled `bootc upgrade`. A host that still trusts the old key will accept
whatever the holder signs. Do not use the planned rotation here: its overlap
keeps the old key trusted.

## Re-signing an older digest

To roll a tag back to an image built before signing began, or signed with a
key since rotated, sign that digest with the current key before moving the
tag. Otherwise hosts refuse it. `bootc rollback` needs no signature, because
it pulls nothing.
