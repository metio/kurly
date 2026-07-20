<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# glitchtip

[GlitchTip](https://glitchtip.com/) — an open-source, Sentry-compatible error-tracking
and performance-monitoring platform. Two composable stages: `server` (the web/ingest
API, `kurly.http`) and `worker` (the Celery worker with beat, `kurly.worker`), on the
official image, backed by an external PostgreSQL and Redis.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local glitchtip = import 'github.com/metio/kurly/workloads/glitchtip/server.libsonnet';
local worker = import 'github.com/metio/kurly/workloads/glitchtip/worker.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='glitchtip-db', database='glitchtip')).items,
  kurly.list(valkey(name='glitchtip-cache')).items,
  kurly.list(glitchtip(domain='https://errors.example.com')).items,
  kurly.list(worker()).items,
]))
```

### `server`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `glitchtip` | |
| `image` | `docker.io/glitchtip/glitchtip:v6.2.2` | |
| `redisHost` | `glitchtip-cache` | the Redis/valkey Service |
| `domain` | inferred | the public URL |
| `secretName` | `glitchtip-secrets` | Secret with `DATABASE_URL` and `SECRET_KEY` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

### `worker`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `glitchtip-worker` | |
| `image` / `redisHost` / `secretName` | as the server | runs `./bin/run-celery-with-beat.sh` |
| `replicas` | `1` | scale out freely — workers coordinate through Redis |
| `env` / `resources` / `labels` / `annotations` | | |

The server serves the web app and the Sentry-compatible ingest API on `:8080` — compose
an exposure onto it.

## Database, cache, and secrets

GlitchTip reads `DATABASE_URL` (with the database password embedded) and `SECRET_KEY`
from a provided Secret via `envFrom`, and `REDIS_URL` and its domain from env. The
defaults pair with a [cnpg-cluster](../cnpg-cluster/) named `glitchtip-db` and a
[valkey](../valkey/) `cache` named `glitchtip-cache`. kurly authors **no Secret** — fill
`glitchtip-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

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
metadata: { name: kurly, namespace: glitchtip }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-glitchtip, namespace: glitchtip }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/glitchtip, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: glitchtip }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-glitchtip, namespace: glitchtip }
spec: { sourceRef: { kind: OCIRepository, name: kurly-glitchtip } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: glitchtip-server, namespace: glitchtip }
spec:
  serviceAccountName: glitchtip-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/glitchtip/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-glitchtip, importPath: github.com/metio/kurly/workloads/glitchtip }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: glitchtip-worker, namespace: glitchtip }
spec:
  serviceAccountName: glitchtip-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local worker = import 'github.com/metio/kurly/workloads/glitchtip/worker.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(worker())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-glitchtip, importPath: github.com/metio/kurly/workloads/glitchtip }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: glitchtip, namespace: glitchtip }
spec:
  serviceAccountName: glitchtip-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: glitchtip-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: glitchtip-server }
    - name: worker
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: glitchtip-worker
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: glitchtip-worker }
```

<!-- END generated: jaas-deploy -->
