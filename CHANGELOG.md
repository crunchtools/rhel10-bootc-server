# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
