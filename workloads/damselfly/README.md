<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# damselfly

[Damselfly](https://github.com/Webreaper/Damselfly) — server-based photo management
that indexes a picture library and finds people and objects in it with local ML
models. A plain composable `kurly.http` workload on the official image, keeping its
SQLite database and generated thumbnails on PersistentVolumes alongside the library it
scans. No external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local damselfly = import 'github.com/metio/kurly/workloads/damselfly/server.libsonnet';

kurly.list(damselfly())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `damselfly` | |
| `image` | pinned by digest | |
| `pictureSize` | `100Gi` | the library at `/pictures` |
| `configSize` | `10Gi` | database, logs and settings at `/config` |
| `thumbsSize` | `20Gi` | the thumbnail cache at `/thumbs` |
| `storageClass` | cluster default | for all three claims |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:6363` — compose an exposure onto it.

## Storage

The entrypoint runs the server against three fixed paths, so this composes
`kurly.store` three times, one PVC each: `/pictures` (add photographs there for it to
index), `/config` and `/thumbs`. Size `pictureSize` to the library you intend to keep.

## Security and persistence

The image declares no `USER` and the server writes into its own install tree at `/app`
(fonts it installs, the ML models it unpacks), so the stage runs it as root with a
writable root filesystem. Capabilities stay dropped and privilege escalation stays
refused.

Indexing and recognition run in-process on start, so the first boot over a large
library is slow and CPU-hungry: a startup probe carries that wait rather than a
stretched liveness delay. The volumes are ReadWriteOnce and one SQLite database backs
the app, so this is **one replica, recreated** (never rolled).

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
metadata: { name: kurly, namespace: damselfly }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-damselfly, namespace: damselfly }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/damselfly, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: damselfly }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-damselfly, namespace: damselfly }
spec: { sourceRef: { kind: OCIRepository, name: kurly-damselfly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: damselfly, namespace: damselfly }
spec:
  serviceAccountName: damselfly-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/damselfly/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-damselfly, importPath: github.com/metio/kurly/workloads/damselfly }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: damselfly, namespace: damselfly }
spec:
  serviceAccountName: damselfly-deployer
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
        name: damselfly
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: damselfly }
```

<!-- END generated: jaas-deploy -->
