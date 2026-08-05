<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pinchflat

[Pinchflat](https://github.com/kieraneglin/pinchflat) — an automated YouTube
archiver built on yt-dlp. Point it at channels or playlists and it downloads new
uploads on a schedule, named and tagged so a media server picks them up. A plain
composable `kurly.http` workload with two PersistentVolumes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pinchflat = import 'github.com/metio/kurly/workloads/pinchflat/server.libsonnet';

kurly.list(pinchflat())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `pinchflat` | |
| `image` | `ghcr.io/kieraneglin/pinchflat:v2025.6.6` | |
| `storageSize` | `2Gi` | SQLite and configuration (`/config`) |
| `mediaSize` | `100Gi` | downloaded media (`/downloads`) |
| `storageClass` | cluster default | both volumes |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web UI on `:8945`:

```jsonnet
kurly.list([
  pinchflat()
  + kurly.expose.ownGateway('archive.example.com', 'istio', tls='pinchflat-tls'),
  kurly.certificate('pinchflat-tls', ['archive.example.com'], 'letsencrypt-prod'),
])
```

There is no authentication in front of it — anyone who reaches the UI can add
sources and browse what has been downloaded. Put an authenticating proxy in front
if it is reachable from anywhere untrusted.

## Two volumes, sized very differently

The database is small and roughly fixed; the media directory is the half that
grows without limit, because a few subscribed channels fill tens of gigabytes.
They are separate parameters so the expensive one can be sized — and given a
different storage class — without dragging the other with it.

## It checks every path before it starts

Pinchflat verifies each directory it uses at startup and exits on the first
read-only one. That is why `/etc/yt-dlp` is scratch alongside `/tmp`: it is not a
path this workload writes anything meaningful to, but the check fails there and
the failure is opaque —

```text
Permissions check failed: {:error, :erofs}
** (RuntimeError) Unknown error
```

— naming the errno and then discarding it. The directory holds only an empty
`plugins/` tree, so an emptyDir satisfies the check without hiding anything.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled) — which keeps two pods off the file and, just as
importantly, two schedulers off the same downloads.

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
metadata: { name: kurly, namespace: pinchflat }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-pinchflat, namespace: pinchflat }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/pinchflat, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: pinchflat }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-pinchflat, namespace: pinchflat }
spec: { sourceRef: { kind: OCIRepository, name: kurly-pinchflat } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: pinchflat, namespace: pinchflat }
spec:
  serviceAccountName: pinchflat-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/pinchflat/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-pinchflat, importPath: github.com/metio/kurly/workloads/pinchflat }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: pinchflat, namespace: pinchflat }
spec:
  serviceAccountName: pinchflat-deployer
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
        name: pinchflat
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: pinchflat }
```

<!-- END generated: jaas-deploy -->
