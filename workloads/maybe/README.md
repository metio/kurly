<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# maybe

[Maybe](https://github.com/maybe-finance/maybe) — a self-hosted personal finance
and net-worth manager. A plain composable `kurly.http` workload backed by an
external PostgreSQL and Redis, with its Active Storage uploads on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local maybe = import 'github.com/metio/kurly/workloads/maybe/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.list([
  cnpg(name='maybe-db', database='maybe'),
  valkey(name='maybe-cache'),
  maybe(),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `maybe` | |
| `image` | `ghcr.io/maybe-finance/maybe:0.1.0-alpha.6` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | Active Storage uploads (`/rails/storage`) |
| `dbHost` / `dbName` / `dbUser` | `maybe-db-rw` / `maybe` / `maybe` | the PostgreSQL database |
| `redisHost` | `maybe-cache` | the Redis/valkey Service |
| `secretName` | `maybe-secrets` | Secret with `POSTGRES_PASSWORD` and `SECRET_KEY_BASE` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:3000` — compose an exposure onto it.

## Database, cache, and secrets

Maybe reads its database and Redis coordinates and its `SECRET_KEY_BASE` from the
environment. The non-secret coordinates default to a [cnpg-cluster](../cnpg-cluster/)
named `maybe-db` and a [valkey](../valkey/) `cache` named `maybe-cache`; the
sensitive values come from a provided Secret via `envFrom`. kurly authors **no
Secret** — fill `maybe-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The Rails app writes to several paths under `/rails` at runtime, so this workload
relaxes kurly's read-only-rootfs default while keeping non-root, dropped
capabilities, and no privilege escalation. Active Storage uploads live on a
ReadWriteOnce volume, so this is **one replica, recreated**. A separate Sidekiq
worker (background jobs) can be added as a second deployment.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: maybe }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-maybe, namespace: maybe }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/maybe, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: maybe }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-maybe, namespace: maybe }
spec: { sourceRef: { kind: OCIRepository, name: kurly-maybe } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: maybe, namespace: maybe }
spec:
  serviceAccountName: maybe-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/maybe/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-maybe, importPath: github.com/metio/kurly/workloads/maybe }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: maybe, namespace: maybe }
spec:
  serviceAccountName: maybe-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: maybe
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: maybe }
```

<!-- END generated: jaas-deploy -->
