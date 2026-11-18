# Lotor on the Nanode (a116, RT#1638)

Host config staged for moving mail.crunchtools.com from Linode 93051850 to
Nanode 111240625. Lotor's IPv4 172.105.105.45 moves to the Nanode with it.
The Nanode is mail-only.

- `nftables-lotor.conf`: Lotor's firewall trimmed to 22422, 25, ICMP and the
  podman bridges. Installs to `/etc/nftables-lotor.conf` with Lotor's
  `lotor-firewall.service`.
- `mail-tunnel-gloval.service`: Lotor's unit without the two NRPE reverse
  forwards (`-R 10.88.0.1:1566x`), since no agent runs any more. Install it
  disabled and enable it only after the IP swap: two tunnels would collide on
  gloval's forwards.

Copied host-to-host from Lotor, and never through git: the files under
`/srv/mail.crunchtools.com/config/` (with `dkim/` and the TLS key),
`/etc/mail-tunnel/`, `mail.crunchtools.com.service`, `lotor-firewall.service`,
`sshd_config.d/99-custom.conf`, `sysctl.d/50-lotor-vm.conf` and
`journald.conf.d/size-limit.conf`.
