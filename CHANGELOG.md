# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `linux-mcp-server` 1.8.0 (rhel-lightspeed), pinned, installed with `uv` into
  `/usr/lib/linux-mcp-server` with its entry point on `/usr/bin`. Host
  administration for the Josui Prime agent, reached only through the Trentina
  gateway, so every call is judged, audited and counted there (RT #1568). It
  replaces nothing: the `josui-rescue` forced-command ssh key stays as the
  floor for a gateway outage, which is the one failure it was built for.

  Shipped **disabled**, with an authorization policy at
  `/etc/linux-mcp-server/policy.yaml` and a unit at
  `/usr/lib/systemd/system/linux-mcp-server.service`. The unit carries
  `ConditionPathExists` on an env file that is not in the image, because that
  file holds the gatekeeper API key and is per-host; a host that was never
  given one does not start the service.

  It runs as root with no systemd sandboxing, deliberately -- it administers
  the host, and a sandboxed copy could not. The controls are elsewhere: a
  specific bind address on the bridge the gateway reaches this host on, an
  nftables rule in the host's own config admitting only the gateway to that
  port, the gateway's judging and audit, and upstream's gatekeeper model
  reviewing each script before it runs.

  `/usr/libexec/linux-mcp-server-preflight` enforces the two of those the
  host can check for itself. It refuses to start on a wildcard bind, by
  `ipaddress.is_unspecified` rather than a list of spellings, since `::`
  has several. And it refuses to start unless the nftables fence is loaded
  *and* is a fence: it reads `nft -j` and checks that every rule accepting
  the port pins both the source address and the bridge interface, that an
  *unconditional* drop exists on tcp in a chain that hooks input, and that the accept precedes it. The drop has
  to narrow itself by nothing but the port: one aimed at a third address
  fences nobody, and one bound to a single `daddr` leaves the port open on
  every other local address. A table that accepted the port from anywhere and
  dropped something unrelated would pass a grep, and is the mistake most
  worth catching. That turns "fence first,
  then the env file" from a deployment convention into a precondition.

  Self-tested at build time: the policy file is parsed with upstream's own
  parser (a policy that fails to load is a silent deny-all on the repair
  tool), the bind check is run against six addresses it must refuse, and the
  fence check against nftables' own JSON taken from the live table and then
  broken nine ways. Those fixtures stay in the image under
  `/usr/share/linux-mcp-server/testdata` so the check can be re-run on a host.

  The unit documents the five per-host variables the env file holds. There is
  no example file, because one of them is a credential and two places to look
  for the same list is one too many.

### Changed
- Constitution is now a v1.18.0 manifest under the Bootc Image profile
  (was Container Image); it records the host role, units, packages, RHSM,
  log forwarding and Podman tuning, and drops the stale httpd and weekly-cron
  entries.
- Constitution validation pinned to v1.18.0 via `constitution.yml`.
- Dependabot auto-merges GitHub Actions minor and patch updates.
- Podman `exit_command_delay` lowered from 300s to 30s (RT #1513). Each API
  exec session keeps two conmon processes alive for that long after the
  command exits, so at 1-minute Nagios check intervals the default held
  ~500 idle processes on lotor.

## [1.1.0] - 2026-09-24

### Added
- petit, the log analyzer, installed from the signed crunchtools
  repository (crunchtools.github.io/packages). The repo definition and its
  key ship with the image, next to EPEL's, because the build needs them.

## [1.0.0] - 2026-09-20

First tagged release. This image has been running in production since before
it had version control; this release marks the current state as the baseline
going forward.
