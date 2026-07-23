<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# paperless-ngx

[Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) — scan, index, and
archive your documents with OCR and full-text search. A plain composable
`kurly.http` workload backed by an external PostgreSQL and Redis, with its data,
media, consume, and export trees on a PersistentVolume. The image runs the web
server and its Celery workers together, so one deployment is the whole app.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local paperless = import 'github.com/metio/kurly/workloads/paperless-ngx/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.list([
  cnpg(name='paperless-db', database='paperless'),
  valkey(name='paperless-cache'),
  paperless(url='https://paperless.example.com'),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `paperless-ngx` | |
| `image` | `ghcr.io/paperless-ngx/paperless-ngx:2.20.15` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | the document archive (data/media/consume/export) |
| `dbHost` / `dbName` / `dbUser` | `paperless-db-rw` / `paperless` / `paperless` | the PostgreSQL database |
| `redisHost` | `paperless-cache` | the Redis/valkey Service |
| `url` | inferred | the public URL |
| `adminUser` | `admin` | the first-run admin username |
| `secretName` | `paperless-ngx-secrets` | Secret with `PAPERLESS_DBPASS`, `PAPERLESS_SECRET_KEY`, `PAPERLESS_ADMIN_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:8000` — compose an exposure onto it.

## Database, cache, and secrets

Paperless reads its database and Redis coordinates and its secrets from the
environment. The non-secret coordinates default to a [cnpg-cluster](../cnpg-cluster/)
named `paperless-db` and a [valkey](../valkey/) `cache` named `paperless-cache`; the
sensitive values come from a provided Secret via `envFrom`. kurly authors **no
Secret** — fill `paperless-ngx-secrets` with
[`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The entrypoint and Celery workers write to the root filesystem, so this workload
relaxes kurly's read-only-rootfs default while keeping non-root, dropped
capabilities, and no privilege escalation. The document archive lives on a
ReadWriteOnce volume (four trees under one volume), so this is **one replica,
recreated**.

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
metadata: { name: kurly, namespace: paperless-ngx }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-paperless-ngx, namespace: paperless-ngx }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/paperless-ngx, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: paperless-ngx }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-paperless-ngx, namespace: paperless-ngx }
spec: { sourceRef: { kind: OCIRepository, name: kurly-paperless-ngx } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: paperless-ngx, namespace: paperless-ngx }
spec:
  serviceAccountName: paperless-ngx-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/paperless-ngx/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-paperless-ngx, importPath: github.com/metio/kurly/workloads/paperless-ngx }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: paperless-ngx, namespace: paperless-ngx }
spec:
  serviceAccountName: paperless-ngx-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: paperless-ngx
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: paperless-ngx }
```

<!-- END generated: jaas-deploy -->
