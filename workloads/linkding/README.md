<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# linkding

[linkding](https://github.com/sissbruecker/linkding) — a minimal, self-hosted
bookmark manager. A plain composable `kurly.http` workload that keeps its bookmarks
in a SQLite database on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local linkding = import 'github.com/metio/kurly/workloads/linkding/server.libsonnet';

kurly.list(linkding())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `linkding` | |
| `image` | `docker.io/sissbruecker/linkding:1.46.0` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the SQLite data volume (`/etc/linkding/data`) |
| `env` | `{}` | extra `LD_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:9090` — compose an exposure onto it. Point
`LD_DB_ENGINE` at an external PostgreSQL through `env` to scale past the single
SQLite writer.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica, recreated**
— the same single-writer discipline as [vaultwarden](../vaultwarden/).

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage. Delivered end to end through Flux, JaaS and stageset-controller on 2026-07-30, and observed rolling out.

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
metadata: { name: kurly, namespace: linkding }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-linkding, namespace: linkding }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/linkding, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: linkding }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-linkding, namespace: linkding }
spec: { sourceRef: { kind: OCIRepository, name: kurly-linkding } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: linkding, namespace: linkding }
spec:
  serviceAccountName: linkding-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/linkding/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-linkding, importPath: github.com/metio/kurly/workloads/linkding }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: linkding, namespace: linkding }
spec:
  serviceAccountName: linkding-deployer
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
        name: linkding
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: linkding }
```

<!-- END generated: jaas-deploy -->
