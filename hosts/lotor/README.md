# Lotor on the Nanode (a116, RT#1638)

mail.crunchtools.com moved on 2026-11-21 from Linode 93051850 (g6-standard-6,
$96/mo, since deleted) to Nanode 111240625 (g6-nanode-1, $5/mo), with Lotor's
IPv4 172.105.105.45 and label. The Nanode is mail-only: the postfix container
and the tunnel to gloval. Nagios watches it agentless, so no agent runs.

- `nftables-lotor.conf`: Lotor's firewall trimmed to 22422, 25, ICMP and the
  podman bridges. Installs to `/etc/nftables-lotor.conf` with Lotor's
  `lotor-firewall.service`.
- `mail-tunnel-gloval.service`: Lotor's unit without the two NRPE reverse
  forwards (`-R 10.88.0.1:1566x`), since no agent runs any more. Never run two
  copies: they collide on gloval's forwards.

Copied host-to-host from Lotor, and never through git: the files under
`/srv/mail.crunchtools.com/config/` (with `dkim/` and the TLS key),
`/etc/mail-tunnel/`, `mail.crunchtools.com.service`, `lotor-firewall.service`,
`sshd_config.d/99-custom.conf`, `sysctl.d/50-lotor-vm.conf` and
`journald.conf.d/size-limit.conf`.

## Rebuilding it

The disk.yml raw is 10 GiB and Linode refuses images over 6 GiB, so it is
written straight onto a raw disk:

1. Create a Debian disk (5 GiB, root key in `authorized_keys`) and a raw disk
   for the rest, boot a config with the helper as sda and the raw as sdb.
2. `gunzip -c disk.raw.gz | ssh root@<ip> dd of=/dev/sdb bs=4M conv=fsync`,
   then grow partition 4 and its XFS from the helper.
3. Point the direct-disk config at the raw alone, delete the helper disk.
4. On first boot: `semanage port -a -t ssh_port_t -p tcp 22422` before the
   firewall closes 22, create the `mail` podman network
   (`--subnet 10.89.1.0/24 --gateway 10.89.1.1`), and plain
   `bootc switch quay.io/crunchtools/rhel10-bootc-server:latest`.
