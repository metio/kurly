<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# twenty

[Twenty](https://github.com/twentyhq/twenty) — a modern, open-source CRM. Two
composable stages: `server` (the web/API front end, `kurly.http`) and `worker` (the
background BullMQ worker, `kurly.worker`), on the official image, backed by an
external PostgreSQL and Redis.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local twenty = import 'github.com/metio/kurly/workloads/twenty/server.libsonnet';
local worker = import 'github.com/metio/kurly/workloads/twenty/worker.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='twenty-db', database='twenty')).items,
  kurly.list(valkey(name='twenty-cache')).items,
  kurly.list(twenty(serverUrl='https://crm.example.com')).items,
  kurly.list(worker()).items,
]))
```

### `server`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `twenty` | |
| `image` | `docker.io/twentycrm/twenty:v2.22.0` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | local uploads |
| `redisHost` | `twenty-cache` | the Redis/valkey Service |
| `serverUrl` | inferred | the public URL |
| `secretName` | `twenty-secrets` | Secret with `PG_DATABASE_URL` and `APP_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

### `worker`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `twenty-worker` | |
| `image` / `redisHost` / `secretName` | as the server | runs `yarn worker:prod` |
| `replicas` | `1` | scale out freely — workers coordinate through Redis |
| `env` / `resources` / `labels` / `annotations` | | |

The server serves the app and API on `:3000` — compose an exposure onto it.

## Database, cache, and secrets

Twenty reads `REDIS_URL` and its server URL from env, and `PG_DATABASE_URL` (with
the database password embedded) and `APP_SECRET` from a provided Secret via
`envFrom`. The defaults pair with a [cnpg-cluster](../cnpg-cluster/) named
`twenty-db` and a [valkey](../valkey/) `cache` named `twenty-cache`. kurly authors
**no Secret** — fill `twenty-secrets` with
[`kurly.externalSecret`](../../main.libsonnet).

## Persistence

With local file storage the server keeps uploads on a ReadWriteOnce volume, so it is
**one replica, recreated**. Move `STORAGE_TYPE` to S3 (the [seaweedfs](../seaweedfs/)
workload) to scale the front end horizontally; the worker holds no state and scales
with `replicas`.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: twenty }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-twenty, namespace: twenty }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/twenty, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: twenty }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-twenty, namespace: twenty }
spec: { sourceRef: { kind: OCIRepository, name: kurly-twenty } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: twenty-server, namespace: twenty }
spec:
  serviceAccountName: twenty-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/twenty/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-twenty, importPath: github.com/metio/kurly/workloads/twenty }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: twenty-worker, namespace: twenty }
spec:
  serviceAccountName: twenty-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local worker = import 'github.com/metio/kurly/workloads/twenty/worker.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(worker())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-twenty, importPath: github.com/metio/kurly/workloads/twenty }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: twenty, namespace: twenty }
spec:
  serviceAccountName: twenty-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: twenty-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: twenty-server }
    - name: worker
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: twenty-worker
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: twenty-worker }
```

<!-- END generated: jaas-deploy -->
