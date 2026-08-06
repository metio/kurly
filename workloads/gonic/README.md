<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gonic

[gonic](https://github.com/sentriz/gonic) — a music streaming server speaking the
Subsonic API, so the Subsonic/Airsonic clients you already use work against it. A
plain composable `kurly.http` workload on the official image: its SQLite database,
cache, podcasts and playlists live on a PersistentVolume, and it reads the music
library from the same volume — no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gonic = import 'github.com/metio/kurly/workloads/gonic/server.libsonnet';

kurly.list(gonic())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `gonic` | |
| `image` | `docker.io/sentriz/gonic:v0.22.0` | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | database, music, cache, podcasts, playlists |
| `port` | `8080` | also written to `GONIC_LISTEN_ADDR` |
| `env` | `{}` | extra `GONIC_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and Subsonic API on `:8080` — compose an exposure onto it. Put
your music under the volume's `music/` directory; it is mounted read-only.

The image listens on `:80`, which an unprivileged process cannot bind, so the stage
moves the listener to `:8080` rather than granting `NET_BIND_SERVICE`, and runs as
an ordinary user.

Every gonic setting is read from a `GONIC_`-prefixed environment variable, which is
also the shape of the Service link variables Kubernetes injects for a Service named
`gonic` — service links are therefore off.

## Persistence

The database lives on a ReadWriteOnce volume, so this is **one replica, recreated** —
the same single-writer discipline as [navidrome](../navidrome/).

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
metadata: { name: kurly, namespace: gonic }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-gonic, namespace: gonic }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/gonic, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: gonic }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-gonic, namespace: gonic }
spec: { sourceRef: { kind: OCIRepository, name: kurly-gonic } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: gonic, namespace: gonic }
spec:
  serviceAccountName: gonic-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/gonic/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-gonic, importPath: github.com/metio/kurly/workloads/gonic }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: gonic, namespace: gonic }
spec:
  serviceAccountName: gonic-deployer
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
        name: gonic
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: gonic }
```

<!-- END generated: jaas-deploy -->
