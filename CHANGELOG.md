# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.8.0] - 2026-11-25

### Fixed
- **The release states its version** (a1654). `pyproject.toml` carries
  `[project].version` beside `VERSION`, as sdlc's `write` job requires of any
  repository with a `pyproject.toml`; the first 1.8.0 merge was refused
  untagged for stating none. A release moves both.
- **Gourmand passes on main** (#78, a1387). The commit and push hooks were
  refusing every change. Moving to an sdlc that runs Gourmand in the check job
  would also have turned CI red. `tests/signing-key.py` now exits from `main()`,
  and its curve-point and prefix lengths are named constants.
  `sdlc.toml` moves into `pyproject.toml` with
  `skip-stacks = ["python"]`, so sdlc still judges this repo as a bootc image.
  The file also holds the fleet's ruff config (IF001), and a `ruff-check`
  pre-commit hook at ruff 0.17.1 lints `tests/*.py`. Ruff's findings in
  `tests/oci-registry.py`, implicit returns from the handlers, are fixed too.
  Re-run `pre-commit install` to wire the new pre-merge-commit hook.

### Changed
- **Signature policy covers all of `quay.io/crunchtools`** (#47). The two
  scoped `rhel10-bootc-*` entries become one namespace entry, so a stolen Quay
  token can no longer swap a service image that `podman auto-update` pulls
  nightly. Hosts refuse every unsigned `quay.io/crunchtools` image from the
  first boot of this image, so it ships only once every image in use is signed
  (a1028 signed the last ones Exedore and Gloval pull). `sdlc` and
  `sdlc-bootstrap` are the two exceptions: their releases carry sdlc's own key,
  not the fleet key, so their scopes accept either key
  (`etc/pki/sigstore/crunchtools-sdlc.pub`). `tests/sigpolicy.sh` fails the
  build if any other `quay.io/crunchtools/<repo>` scope in `policy.json` or
  `registries.d` would exempt a repository.
- **digest-gate self-test runs offline** (#76, a1372). `tests/digest-gate.sh`
  no longer reads quay.io: it serves two fixture images from
  `tests/oci-registry.py` on loopback, signs one with a key made for the run,
  and proves the gate refuses the unsigned one, refuses the signed one under
  the production key, and accepts it under the run's key. The check drops
  `network = true`, so a Quay outage or a moved tag no longer fails a pull
  request. The gate itself is unchanged.

## [1.7.0] - 2026-11-24

### Added
- **KVM host packages** (RT #1664): `qemu-kvm`, `qemu-img`, `virtiofsd` and
  `zram-generator`, for Exedore's disposable GitHub Actions runner VMs. Nothing
  is enabled: no libvirt daemon, and `zram-generator` without its defaults
  package, so a host gets zram swap only from its own
  `/etc/systemd/zram-generator.conf`. Gloval and Lotor carry the packages
  unused; one image still serves every host.
- **Releases tagged by the Ashigaru app** (a965). `release.yml` opens a
  release pull request as the app on workflow_dispatch and tags it on merge
  through Ashigaru's `release-tag.yml@v5`; the cosign release-tag ruleset
  refuses `v*.*.*` tags from anyone else. README.md's "How to release" has the
  steps.
- **Lotor's mail-only host config** (a116, RT#1638). `hosts/lotor/` holds the
  trimmed firewall and tunnel unit that mail.crunchtools.com runs on the
  Nanode, plus how to put the disk.yml raw on a Linode: it is 10 GiB, over
  Linode's 6 GiB image cap, so it is written straight onto a raw disk.
- **Signature backfill** (#47, #64). `signing/backfill.txt` lists the 93
  `quay.io/crunchtools` digests hosts run or roll back to that promote will
  never sign (`:latest` from before a repo set `sign: true`, `rollback-*`,
  pinned digests), and the `Backfill signatures` workflow signs each once from
  main in the `cosign-signing` environment, skipping any that already verify.

### Changed
- **The mt76 kmod overlay is retired; hosts run the stock driver** (a912, #70). RHEL's kernel 6.12.0-264.17.1.el10_3
  carries 20b126920a25, so the overlay's guard failed every Container build
  from 11-20 on, as designed. Every piece `kmod/mt76/README.md` listed under
  REMOVING is gone: the builder stage, `kmod/mt76/`,
  `scripts/mt76-apply-fix.sh`, the kmod tests and fixture, the boot gate's
  `modinfo` checks and the constitution paragraph (v1.5.0). exedore's
  mt7925e now runs the stock, fixed driver.

- Gatehouse triage receives the review job's result (`review_result`), so a PR whose review died before posting anything is held instead of passing.
- The container release runs constitution v1.51.0's `container-release.yml`
  (was v1.46.0) and grants it `issues: write`, so a failed weekly rebuild opens
  an issue instead of only emailing whoever last touched the cron line. A `v*`
  promote now also refuses an image whose `version` label names a different
  release of this repo; this image sets none and inherits rhel-bootc's, which
  is not compared.

### Fixed
- **mt76 overlay review notes** (#60). A failed `install` of an overlay module
  now fails the build: `find -exec … \;` had exited 0 regardless. The
  "already carries 20b126920a25" refusal points at a REMOVING list in
  `kmod/mt76/README.md` that names every piece of the overlay, and the patch
  pin is described as this repo's copy of 20b126920a25 rather than a hash of
  what git.kernel.org serves.

## [1.6.0] - 2026-11-18

### Added
- **mt76 kmod overlay with upstream 20b126920a25** (RT#1656). mt7925e hit
  kernel BUG list_debug.c:32 in `mt7925_mac_add_txs` when a station was
  re-added under traffic, and the card wedged until a power-off. A builder
  stage rebuilds the mt76 tree from the image kernel's source RPM with the
  upstream fix (pinned by sha256) and installs it to `updates/`. The build
  fails if the kernel already has the fix, if the patch stops applying, or if
  the kernel moved between stages. `tests/kmod-mt76.sh` and the boot gate
  check that `modinfo mt7925e` resolves to the overlay.
- **Raw disk images from a signed digest** (RT#1638). `disk.yml` is dispatched
  with a digest, refuses one the bootc key did not sign, and builds a
  bootc-image-builder raw disk with root keyed from
  `install/root-authorized-keys`, uploaded as a workflow artifact. It is how a
  Linode host gets the image: `bootc install to-existing-root` cannot work on
  Linode's unpartitioned disks.
  The disk boots pinned to the digest; `bootc switch` it to `:latest` after
  first boot, a pull the shipped policy verifies.
  It builds only when dispatched from `main` or a `v*` tag, since the root key
  comes from the checked-out ref. The signature gate is `tests/digest-gate.sh`,
  whose self-test refuses malformed and unsigned digests on every pull request.

## [1.5.0] - 2026-11-18

### Added
- **Wi-Fi watchdog** (a301). On 2026-11-18 an AP channel switch left exedore's
  Wi-Fi "connected" with a dead gateway for thirteen minutes, until someone ran
  `nmcli con up` by hand. `wifi-watchdog.timer` pings the connection's gateway
  every 30 seconds and re-activates the connection after 3 consecutive misses,
  at most once per 5 minutes, logging to the journal as `wifi-watchdog`. It
  starts only on a host with `/etc/sysconfig/wifi-watchdog`
  (`WIFI_WATCHDOG_CONNECTION=<id>`); `install/wifi.ks.example` writes it.

### Fixed
- `install/wifi.ks.example` no longer leaves two profiles for one SSID: `%post`
  writes its own only when Anaconda did not copy the installer's, and names it
  after the SSID.
- `install/wifi.ks.example` takes the SSID and PSK as data through quoted
  heredocs: a quote or a `$` in either no longer breaks, or runs as shell in,
  `%pre` and `%post`.

## [1.4.0] - 2026-11-17

### Changed
- Signing moves into the constitution's `container-release.yml` (v1.44.0,
  `sign: true`, #47): promote signs the digest before any tag moves, so a tag
  never points at an unsigned image, even briefly. The local `sign` job is
  gone. Rotating the signing key now also needs a constitution release
  (`docs/signing-key.md`).

## [1.3.1] - 2026-11-17

### Security
- **Hosts accept only signed bootc images** (#44). The pipeline signs every
  promoted digest (merge to main, v* release, weekly rebuild; never a pull
  request candidate) with cosign, and the image ships a `sigstoreSigned`
  policy for `quay.io/crunchtools/rhel10-bootc-server` and `-workstation`, the
  matching registries.d entry and the public key. A stolen Quay token can
  still move a tag, but no host will upgrade to what it points at. The default
  policy and the Red Hat entries are unchanged; the rest of
  quay.io/crunchtools stays unsigned until #47. The signing key lives only in
  the `cosign-signing` environment (main and v* tags), and a v* tag off main
  is never signed. Rotation and loss runbook: `docs/signing-key.md`.

## [1.3.0] - 2026-11-13

### Changed
- **Each host can choose where it ships its logs** (RT#1628). The forwarder's
  destination moves from a hard-coded `127.0.0.1` in `rsyslog.conf` to
  `RSYSLOG_COLLECTOR`, which an rsyslog drop-in defaults to `127.0.0.1` (gloval,
  where the collector runs) and `/etc/sysconfig/rsyslog-collector` overrides.
  Exedore was the first host that is not gloval, and its forwarder failed to
  connect every ten seconds and spooled to disk. Overlay
  hosts set `RSYSLOG_COLLECTOR=10.44.0.1`; bootc keeps the file across updates.

## [1.2.0] - 2026-11-13

### Added
- **Wi-Fi support** (RT#1628): `NetworkManager-wifi` and `wpa_supplicant`.
  Exedore sits upstairs with no Ethernet run, so it lives on Wi-Fi. The
  MT7925 firmware was already in the image; the NetworkManager plugin and
  supplicant were not, so a Wi-Fi host installed fine and came up offline.
  On hosts with no radio, such as gloval, both stay idle.

## [1.1.1] - 2026-11-11

### Fixed
- **A deferred bootc apply no longer leaves failed units behind** (RT #1566,
  RT #1594). The interlock worked and still reported the host as broken for
  doing so. Every deferral cycle left `bootc-fetch-apply-updates.service` in
  `failed` with `Result=timeout`, because that is how the drop-in's
  `TimeoutStartSec` ends bootc's park on a refused reboot, plus one failed
  transient per refusal — a `run-pNNN-iNNN.service` running
  `systemctl reboot --message=Initiated by bootc`, failed because
  `systemctl reboot` came back non-zero. They accumulate: four on 2026-11-09,
  and gloval's "Host failed systemd units" check sat CRITICAL for over two
  hours while a rotation held an OS update off, then had to be swept by hand.

  That is the alert-fatigue failure RT #1566 is about. A check that goes red
  when nothing is wrong gets acknowledged, and an acknowledged check is not a
  check — so the fix is the host not reporting itself broken, not the monitor
  learning to look away. Nothing in the nagios-agent repo changed.

  `OnFailure=` on the drop-in now points at a new
  `bootc-apply-deferred.service` instead of straight at the retry timer,
  because a dependency cannot tell a deferral from a failure and a decision
  can. It calls `/usr/libexec/bootc-apply-deferred`, which requires three
  facts before it clears anything: the apply unit ended `Result=timeout`; a
  failed transient *from that same run* is running bootc's reboot; and this
  cycle's journal records logind **refusing** it. Only then does it
  `reset-failed` the apply unit and every failed transient attributable to
  bootc's reboot; on anything else it changes no failed state at all and the
  host stays exactly as loud as before. Either way it arms
  `bootc-apply-retry.timer`, which is what pointing at the timer did before.

  The third fact exists because `systemctl reboot` can fail for reasons that
  are nothing to do with a backup, and those are real failures. Without it, a
  host whose reboot kept failing on its own account would be swept clean every
  thirty minutes, never update, and never say so — the exact silence this
  change is meant to be the opposite of. The denial is read from bootc's own
  units over a twenty-minute window — derived from the drop-in's 10-minute
  start timeout and the retry timer's 30-minute cadence — so that one genuine
  deferral earlier in a boot cannot corroborate every real failure after it.
  A window rather than the apply unit's own start converted to a date:
  systemd reports that start on `CLOCK_MONOTONIC`, and converting it drifts by
  however long the host has been suspended, measured at five minutes on a
  laptop here, which would put the window *after* the refusal and lose it.

  It is deliberately *not* the obvious test, "a block shutdown inhibitor is
  held right now". That is the right cause read ten minutes after its own
  effect, since `TimeoutStartSec` is 10 minutes, and it is wrong in both
  directions. It is absent when the rotation ended inside that window: on
  11-09 the refusal was at 02:19:06 and the rotation finished at 02:31:16,
  about two and a half minutes clear of the timeout, one slower start from
  reading a genuine deferral as a failure. And it is present when an unrelated
  rotation merely started after a reboot had already failed for its own
  reasons, which would sweep a real failure. So logind's `BlockInhibited` and
  the block-mode rows of `systemd-inhibit --list` are logged, because they are
  what a person wants to see on a Saturday night, and they decide nothing.

  The matching line has to name the reboot as well as the denial: gloval logged
  `Call to Reboot failed: Access denied`, and a denial from some other
  operation in the same cycle — a registry pull, say — is not evidence about
  this one. `journalctl --grep` does the first pass so a chatty cycle cannot
  push the one line that matters out of a line cap, with an unfiltered re-read
  only when journalctl complains about `--grep` rather than on every real
  failure.

  A diagnostic string is a thin thing to rest on, and it rests the right way
  up: no denial matched means real failure and nothing is touched. If logind's
  wording ever changes, this stops cleaning up and says so in the journal.
  That is the direction every uncertainty here is pointed.

  The twenty minutes is only the right number between the drop-in's
  `TimeoutStartSec` and the timer's `OnActiveSec`, and nothing at runtime can
  notice if one of them moves. The image build asserts all three together.

  Three cases it must not get wrong, and does not. A *successful* apply ends
  `Result=signal`, not `timeout`, and fires this same `OnFailure=` on the way
  down — excluded by name rather than by luck. A timeout with no reboot ever
  attempted, such as a hung fetch, has no transient to point at and stays
  failed, so the interlock cannot become a way to never hear about broken
  updates. And a failed `run-p*` transient belonging to something else is
  identified by its command, not its name, and survives.

  `bootc-apply-deferred.service` has no `[Install]` section, is never enabled
  and starts no apply of its own, the same property `bootc-apply-retry.timer`
  has: masking `bootc-fetch-apply-updates.timer` on this host was meant to
  keep unattended updates off it, and nothing added for the interlock may
  quietly become the path that was masked.

  `--self-test` also checks the subprocess wrapper's four outcomes against
  real commands — `true`, `false` and a path that does not exist — because
  every classification path reads an empty result as absence of evidence and
  therefore as a real failure, so a wrapper that returned output from a failed
  command would move the bias in the one direction it must never move.

  The classifier is self-tested in the image build against nineteen
  host-state fixtures, which stay at
  `/usr/share/bootc-apply-deferred/testdata` so the check can be re-run on a
  host. It is tested because it decides when to erase the evidence of a
  failure, and because the live case cannot be reproduced on gloval without
  holding a block inhibitor through a real apply and waiting out a ten-minute
  timeout.

### Added
- **The interlock's two halves were verified on the live host** (RT #1594),
  with timestamps recorded in the drop-in beside the settings they justify. A
  reboot that bootc requested while a pCloud rotation held the block inhibitor
  was refused outright ("Call to Reboot failed: Access denied") and the
  rotation ran on to a clean finish; the same unit started again with nothing
  holding the lock applied the staged image and rebooted.

  Also documented there: a *successful* apply records
  `Failed with result 'signal'` for this unit in the journal of the boot it
  ends, because the reboot it asked for tears the unit down and its own
  process takes the SIGTERM. `OnFailure=` fires on the way down, the retry
  timer's start job dies with the shutdown, and nothing survives the reboot —
  cosmetic, but it is the expected shape of success, and worth knowing before
  someone reads it as a refused reboot. A refusal looks different: "Access
  denied" in the journal and this unit sitting in `activating` until the start
  timeout cuts it.

- **The bootc apply now defers for a backup instead of killing it** (RT #1594).
  A drop-in on `bootc-fetch-apply-updates.service` and a `bootc-apply-retry`
  timer, the host half of an interlock whose other half is the block shutdown
  inhibitor pbs 2.7.0 holds for the life of every rotation.

  On 2026-11-08 at 03:30 this unit rebooted gloval and SIGKILLed the weekly
  pCloud rotation at 93%, 36 minutes from the end of a ten-hour transfer. Two
  things about it were not what they looked like. The unit is
  `bootc upgrade --apply`, and `--apply` reboots the host itself about twenty
  seconds after staging, so "it only stages" was wrong. And
  `bootc-fetch-apply-updates.timer` is masked here, the service is `static`
  with no triggers, and there is no cron entry or sudo record for it — so
  something starts it over D-Bus, and three runs in seven days at irregular
  hours say it is not a schedule. That caller is still unidentified, which is
  the reason the guard is a lock rather than a condition: it does not need to
  know who asked.

  `TimeoutStartSec=10min`, because bootc calls `systemd-run` without `--wait`.
  systemd-run returns 0 as soon as the transient unit starts and never sees
  `systemctl reboot` exit non-zero, so a refused reboot leaves bootc parked
  forever waiting for a SIGTERM that never arrives. Upstream's bug; bounded
  here until it is fixed. The 11-08 run pulled, staged and rebooted in twenty
  seconds, so ten minutes is thirty times the headroom.

  `OnFailure=bootc-apply-retry.timer`, because a refused reboot otherwise
  leaves the image staged with nothing retrying — skipped, not deferred. The
  timer arms one attempt thirty minutes out, elapses once and goes inactive so
  the next failure re-arms it. A rotation still running refuses again; when it
  finishes, the staged image applies. `bootc upgrade --apply` reboots on an
  unchanged staged deployment, so the retry needs to re-fetch nothing.

  The timer has no `[Install]` section and is never enabled. It exists only
  after an apply has already failed, so this does not quietly become the
  unattended update path that masking the bootc timer was meant to prevent.

### Changed
- `linux-mcp-server` ships the **read-only toolset** (`--toolset fixed`), not
  `both`. Upstream's guarded command execution does not work on this host:
  its gatekeeper cannot open an outbound connection from inside the serving
  process, with any provider, to the internet or to a LAN address, while the
  same interpreter and environment outside the server connect fine. No
  sandboxing, full capabilities, no seccomp filter, same network namespace as
  PID 1 — so it is upstream's, in a feature upstream marks experimental.
  Shipping `both` would offer three tools that always error (RT #1568).

### Fixed
- The `linux-mcp-server` **unit was never copied into the image**. The binary,
  the preflight, its fixtures and the policy all shipped; the one file that
  makes any of it run did not, so gloval came up with everything in place and
  `systemctl status linux-mcp-server` answering "could not be found". Lost
  while rewriting that block of the Containerfile — the edit replaced a span
  that contained the `COPY`, and nothing checked. The build-time policy parse
  went the same way and is restored with it.

  The build now asserts all four artefacts exist before it finishes. A dropped
  `COPY` is not a visible failure otherwise: it produces a host that looks
  configured and has no service.

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
