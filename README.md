# rhel10-bootc-server

The RHEL 10 bootc image for Crunchtools servers. The image is built, signed
and published by GitHub Actions only (`container.yml`); `docs/signing-key.md`
covers the signing key.

## How to release

Only the Ashigaru app may create `v*.*.*` tags here; a tag made by hand is
refused. Most releases need nothing: the Ashigaru sweep opens the release pull
request and tags it when it merges. To cut one yourself:

1. On a branch `chore/release-X.Y.Z`, set `VERSION` to X.Y.Z and roll
   CHANGELOG.md's Unreleased section into `[X.Y.Z]`. Touch nothing else. Push
   it.
2. Run the Release workflow from main with version `X.Y.Z`. The app opens the
   pull request from `ashigaru/release-X.Y.Z`.
3. Merge it. `release.yml` tags the merge commit as the app, which starts the
   `v*` container run.
