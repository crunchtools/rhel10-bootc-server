# rhel10-bootc-server Constitution

> **Version:** 1.0.0
> **Ratified:** 2026-03-03
> **Status:** Active
> **Inherits:** [crunchtools/constitution](https://github.com/crunchtools/constitution) v1.0.0
> **Profile:** Container Image

RHEL 10 bootc server image for hosting container workloads. Server-oriented (no GUI/Workstation group). Primary use case: Linode VPS running Podman containers behind Apache reverse proxy.

---

## License

AGPL-3.0-or-later

## Versioning

Follow Semantic Versioning 2.0.0. MAJOR/MINOR/PATCH.

## Base Image

`registry.redhat.io/rhel10/rhel-bootc:latest` — bootc-enabled RHEL 10 for image mode deployments with atomic updates and rollback. Hosted containers use UBI10 base images (e.g., `registry.redhat.io/ubi10/ubi-init`, `registry.redhat.io/ubi10/ubi-minimal`).

## Registry

Published to `quay.io/crunchtools/rhel10-bootc-server`.

## RHSM Registration

Uses `--mount=type=secret` based subscription-manager registration at build time to access RHEL repos. Secrets never baked into image layers.

## Containerfile Conventions

- Uses `Containerfile` (not Dockerfile)
- `dnf install -y --nodocs` followed by `dnf clean all`
- `subscription-manager unregister` after package installation
- systemd services enabled: httpd, cockpit.socket, podman-auto-update.timer, fstrim.timer
- `systemctl set-default multi-user.target` (headless server)
- EPEL repository for rclone, gh, uv
- `bootc container lint` as final build step

## Packages Installed

httpd, mod_ssl, cockpit, git, vim-enhanced, nodejs24, python3-pip, python3-devel, sqlite, rclone, gh, uv

## Testing

- **Build test**: CI builds the image on every push to main
- **Weekly rebuild**: Picks up base image and package updates every Monday 6 AM UTC

## Quality Gates

1. Build — CI builds the Containerfile successfully
2. Weekly rebuild — cron job picks up base image updates every Monday 6 AM UTC
