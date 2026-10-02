# rhel10-bootc-server Constitution

> **Version:** 1.1.0
> **Ratified:** 2026-03-03
> **Amended:** 2026-10-02
> **Status:** Active
> **Inherits:** [crunchtools/constitution](https://github.com/crunchtools/constitution) v1.18.0
> **Profile:** Bootc Image

This file holds what is specific to rhel10-bootc-server. The fleet rules and
the Bootc Image profile apply at the inherited version and are checked
against this repo's files by `constitution.yml`. They are not restated here.

## Host Role

Headless RHEL 10 server (`multi-user.target`, no GUI or Workstation group)
for a VPS that runs Podman containers. The containers it hosts are built on
UBI10 (`registry.redhat.io/ubi10/ubi-init`, `ubi10/ubi-minimal`) and update
through `podman-auto-update.timer`.

- **Base image:** `registry.redhat.io/rhel10/rhel-bootc` (no crunchtools
  parent; this image is the top of its cascade).
- **Image:** `quay.io/crunchtools/rhel10-bootc-server`, mirrored to GHCR.
- **Enabled units:** `cockpit.socket` (web console), `podman-auto-update.timer`
  (container updates), `fstrim.timer` (periodic TRIM),
  `systemd-oomd.service` (memory pressure), `sysstat.service` (sar data collection),
  `rsyslog.service` (log forwarding, aliased as `syslog.service`).
- **Packages:** cockpit, petit, git, vim-enhanced, nodejs24 (with
  `node`/`npm`/`npx` symlinks), python3-pip, python3-devel, sqlite, rclone,
  rsyslog, gh, uv, sysstat, systemd-oomd.
- **Repositories:** EPEL (rclone, gh, uv) and the signed crunchtools
  repository at `crunchtools.github.io/packages` (petit); both repo files and
  GPG keys ship in `etc/` because the build needs them.
- **Timezone:** America/New_York. Shell history settings and
  `RCLONE_CONFIG=/etc/rclone.conf` come from `etc/bashrc.customizations`.

## RHSM Registration

The build registers with subscription-manager from the `activation_key` and
`org_id` build secrets (`--mount=type=secret`) and unregisters before the
final layers, so neither the secrets nor the registration reach the image.
After `dnf update`, every kernel but the newest is removed so `bootc
container lint` passes.

## Log Forwarding

`etc/rsyslog.conf` replaces the stock RHEL file. journald forwards to the
syslog socket (`ForwardToSyslog=yes`) and rsyslog only relays to a collector
on `127.0.0.1:514` over TCP, with a disk-backed queue (500 MB). The stock
`imjournal` input is not used: it stops following after a journal rotation
and takes the ingest path down silently. The rsyslog drop-in makes
`syslog.socket` an explicit dependency so forwarded messages always have a
socket to land on. journald's rate limit is raised to 20000 messages per 30s.
The journal stays persistent so `podman logs` keeps working.

## Podman Tuning

`exit_command_delay = 30` (Docker-compat default 300s): each API exec
session holds two conmon processes until the delay expires, and 1-minute
monitoring checks otherwise left hundreds idle (RT #1513).

## History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-03-03 | Initial server bootc image constitution |
| 1.0.1 | 2026-09-25 | Inherits constitution v1.17.0 (Gatehouse gates) |
| 1.1.0 | 2026-10-02 | Manifest under constitution v1.18.0; profile changed from Container Image to Bootc Image (constitution#22) |
