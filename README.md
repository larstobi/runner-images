# Forgejo runner image

`forgejo-ci` is a Linux/amd64 worker image for the validation workflows in
[`larstobi/k8s-relatime`](https://github.com/larstobi/k8s-relatime). It builds
on the Node 24 Debian Bookworm image used by the existing Forgejo runner, and
keeps the runtime unprivileged. One shared image avoids duplicating the same
tools across six short-lived jobs.

The image contains:

| Used by | Included tools |
| --- | --- |
| All workflows / checkout | Node 24, Git, Bash, curl and CA certificates |
| Python, Talos and manifest checks | Python 3.13, PyYAML 6.0.3, Ansible, Helm 3.18.6, kubectl 1.34.1, talosctl 1.14.2 |
| Grafana Foundation SDK | Go 1.24 |
| Prometheus alert checks | promtool 3.2.1, matching the pinned test image |
| Ansible host safety | rsync, btrfs-progs, fdisk and systemd-repart from Bookworm backports |

Image sources and downloaded binaries are pinned in the Dockerfile. Python
top-level requirements are pinned in `requirements.txt`; Debian packages and
transitive Python dependencies are resolved at build time. Update dependencies
deliberately and run the verification again when the downstream workflow
versions change.

## Build, verify and publish

GitHub Actions builds the image on every PR and on pushes to `main`. Before
publication, it runs `tests/smoke.sh` as UID 1000 with no network, no Linux
capabilities, and a read-only root filesystem. The smoke test exercises the
actual offline repart operation on a disposable sparse file, including
filesystem identification and rejection of a second run.

Only a successful push to `main` publishes that same tested image to GHCR:

- `ghcr.io/larstobi/runner-images/forgejo-ci:sha-<full-commit-sha>`
- `ghcr.io/larstobi/runner-images/forgejo-ci:main`

No image is published by a PR. GHCR may create a new package as private; ensure
the cluster has pull access before consuming it. Use the published **digest**
in GitOps, not the mutable `main` tag, and confirm its architecture is amd64.

## Integration with k8s-relatime

This repository does not change the deployed runner or its workflows. After
the image is published, a separate reviewed GitOps change must select its
digest in the Forgejo worker pod. Preserve its writable `/work` and `/tmp`
volumes, non-root UID/GID 1000, seccomp, dropped capabilities and read-only
root filesystem. The worker creates `HOME` under `/work`; Go caches and other
runtime state must also remain on writable volumes.

The six downstream workflows need corresponding adaptations: use the
preinstalled tools and Python packages instead of installing with `sudo`,
`pip`, or setup actions that expect a writable system tool cache. Run the
Prometheus tests without `--docker` to use the bundled promtool. Go module and
Helm chart downloads may still need network access.

The current PostgreSQL migration, Node-RED authentication, Loki log-query and
Alloy validation steps explicitly invoke Docker and will **not** work with
this image alone. They need an equivalent unprivileged test arrangement or a
separate suitable runner before those workflows can pass. Do not silently
remove these tests. The existing workflows must be exercised in the target
runner after adaptation; the image smoke test is not a substitute for them.
