<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# podfetch

[Podfetch](https://github.com/SamTV12345/PodFetch) — a self-hosted podcast
manager: it subscribes to feeds, downloads the episodes, and plays them in the
browser, with a GPodder endpoint so an existing podcast app keeps syncing against
it. A plain composable `kurly.http` workload on the upstream image, backed by
SQLite, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local podfetch = import 'github.com/metio/kurly/workloads/podfetch/server.libsonnet';

kurly.list(podfetch())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `podfetch` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | the downloaded episodes |
| `databaseSize` | `1Gi` | the SQLite database |
| `pollingInterval` | `60` | MINUTES between feed checks |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:8000` — compose an exposure onto it.

## Persistence

Two volumes, because the two things it keeps grow at completely different rates:
the SQLite database at `/app/db`, and the downloaded audio at `/app/podcasts`,
which is the one that fills a disk. Size them separately.

Both are ReadWriteOnce, so this is **one replica, recreated** — the same
single-writer discipline as [audiobookshelf](../audiobookshelf/).

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
metadata: { name: kurly, namespace: podfetch }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-podfetch, namespace: podfetch }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/podfetch, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: podfetch }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-podfetch, namespace: podfetch }
spec: { sourceRef: { kind: OCIRepository, name: kurly-podfetch } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: podfetch, namespace: podfetch }
spec:
  serviceAccountName: podfetch-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/podfetch/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-podfetch, importPath: github.com/metio/kurly/workloads/podfetch }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: podfetch, namespace: podfetch }
spec:
  serviceAccountName: podfetch-deployer
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
        name: podfetch
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: podfetch }
```

<!-- END generated: jaas-deploy -->
