<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# endurain

[Endurain](https://github.com/joaovitoriasilva/endurain) — a self-hosted fitness
and training-activity tracker. A plain composable `kurly.http` workload backed by
an external PostgreSQL and Redis, with its uploaded activity files and photos on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local endurain = import 'github.com/metio/kurly/workloads/endurain/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.list([
  cnpg(name='endurain-db', database='endurain'),
  valkey(name='endurain-cache'),
  endurain(endurainHost='https://fitness.example.com'),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `endurain` | |
| `image` | `ghcr.io/joaovitoriasilva/endurain:0.17.7` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | uploads (`/app/backend/app`) |
| `dbHost` / `dbName` / `dbUser` | `endurain-db-rw` / `endurain` / `endurain` | the PostgreSQL database |
| `redisHost` | `endurain-cache` | the Redis/valkey Service |
| `endurainHost` | inferred | the public URL |
| `secretName` | `endurain-secrets` | Secret with `DB_PASSWORD` and `SECRET_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:8080` — compose an exposure onto it.

## Database, cache, and secrets

Endurain reads its database and cache coordinates and its `SECRET_KEY` from the
environment. The non-secret coordinates default to a [cnpg-cluster](../cnpg-cluster/)
named `endurain-db` and a [valkey](../valkey/) `cache` named `endurain-cache`; the
sensitive values (`DB_PASSWORD`, `SECRET_KEY`) come from a provided Secret via
`envFrom`. kurly authors **no Secret** — fill `endurain-secrets` with
[`kurly.externalSecret`](../../main.libsonnet).

## Persistence

Uploaded files and photos live on a ReadWriteOnce volume, so this is **one replica,
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
metadata: { name: kurly, namespace: endurain }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-endurain, namespace: endurain }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/endurain, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: endurain }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-endurain, namespace: endurain }
spec: { sourceRef: { kind: OCIRepository, name: kurly-endurain } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: endurain, namespace: endurain }
spec:
  serviceAccountName: endurain-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/endurain/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-endurain, importPath: github.com/metio/kurly/workloads/endurain }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: endurain, namespace: endurain }
spec:
  serviceAccountName: endurain-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: endurain
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: endurain }
```

<!-- END generated: jaas-deploy -->
