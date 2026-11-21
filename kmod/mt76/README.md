# mt76 kmod overlay (RT#1656)

`0001-wifi-mt76-add-wcid-publish-check-in-mt76_sta_add.patch` is upstream
20b126920a25 ("wifi: mt76: add wcid publish check in mt76_sta_add") as
`git format-patch` output. The Containerfile pins this repo's copy of that
commit by sha256 (`MT76_PATCH_SHA256`). It is not a pin of what git.kernel.org
serves today: cgit abbreviates the `index` lines to however many hex digits
the repository currently needs, so a fresh download drifts as the kernel tree
grows even though the change is the same. To check the copy, compare the diff
hunks against 20b126920a25, not the file's hash.

## REMOVING

When the build fails with "already carries 20b126920a25", RHEL has the fix.
Delete all of this in one pull request:

- `kmod/mt76/` (this file and the patch);
- `scripts/mt76-apply-fix.sh`;
- `tests/kmod-mt76.sh`, `tests/kmod-mt76-apply.sh` and `tests/fixtures/mt76/`;
- in `Containerfile`: the `mt76` builder stage and the comment above it, the
  `COPY --from=mt76`, the `depmod` RUN and the `kmod-mt76.sh` RUN after it;
- in `.github/workflows/container.yml`: the `modinfo` line and the two `grep`
  lines in `boot-command` (keep `bootc container lint`), their comment, and
  `kmod/**` in both `paths` filters;
- the "Kernel module overlay" paragraph in `.specify/memory/constitution.md`
  (a constitution amendment: bump its version).

Then `git grep -i mt76` should find only the CHANGELOG.
