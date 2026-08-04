<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# archivebox

[ArchiveBox](https://github.com/ArchiveBox/ArchiveBox) — self-hosted web
archiving. Give it URLs, RSS feeds or bookmark exports and it keeps its own copies
as HTML, PDF, screenshots and WARC. A plain composable `kurly.http` workload: the
archive, its SQLite index and the search index all live on one PersistentVolume,
so it needs nothing external.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local archivebox = import 'github.com/metio/kurly/workloads/archivebox/server.libsonnet';

kurly.list(archivebox())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `archivebox` | |
| `image` | `archivebox/archivebox:stable` | see the note on pinning |
| `storageSize` / `storageClass` | `50Gi` / cluster default | the archive (`/data`) |
| `puid` / `pgid` | `911` | who owns the archive |
| `env` / `resources` / `labels` / `annotations` | | Chrome, so give it memory |

Serves the web UI on `:8000` — compose an exposure onto it:

```jsonnet
kurly.list([
  archivebox()
  + kurly.expose.ownGateway('archive.example.com', 'istio', tls='archivebox-tls'),
  kurly.certificate('archivebox-tls', ['archive.example.com'], 'letsencrypt-prod'),
])
```

## This one is less hardened than the rest, on purpose

Most workloads here keep kurly's `restricted` posture. This one gives up three
things, and each buys a specific step the image cannot take without it:

- **root at startup**, because the entrypoint `usermod`s its own account onto
  `puid`/`pgid`, chowns the data directory and then drops to that account with
  `gosu`. It refuses `PUID=0` outright, so there is no "just run unprivileged"
  path — unlike [opengist](../opengist/) and [cloudbeaver](../cloudbeaver/), whose
  entrypoints branch on whether they are already unprivileged.
- **capabilities and privilege escalation**, which is what `gosu` needs to change
  uid.
- **a writable root filesystem**. This one is worth knowing about before you meet
  it: with a read-only root filesystem the container exits **10 immediately and
  logs nothing at all**. The same image runs perfectly with the filesystem
  writable, so the failure reads as a broken image rather than a denied write.

The archive itself is still written by an unprivileged user.

## Pinning

Upstream publishes release candidates (`0.8.5rcNN`) and a moving `stable` tag,
with no plain version tag for the current release. So the pin here is
`stable@sha256:…`: the digest fixes the bits, which is what reproducibility needs,
while the tag names no version. `stable` was v0.7.4 when this was written.

## Persistence

One SQLite index and one archive tree on a ReadWriteOnce volume, so this is **one
replica, recreated** (never rolled) to keep two pods off the files. The default
request is 50Gi because a real archive of full-page snapshots, PDFs and media
grows quickly — size it for what you intend to keep.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: archivebox }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-archivebox, namespace: archivebox }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/archivebox, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: archivebox }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-archivebox, namespace: archivebox }
spec: { sourceRef: { kind: OCIRepository, name: kurly-archivebox } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: archivebox, namespace: archivebox }
spec:
  serviceAccountName: archivebox-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/archivebox/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-archivebox, importPath: github.com/metio/kurly/workloads/archivebox }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: archivebox, namespace: archivebox }
spec:
  serviceAccountName: archivebox-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: archivebox
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: archivebox }
```

<!-- END generated: jaas-deploy -->
