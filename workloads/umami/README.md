<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# umami

[Umami](https://github.com/umami-software/umami) — a simple, privacy-focused,
self-hosted web-analytics alternative to Google Analytics. A plain composable
`kurly.http` workload on the official image, backed by an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local umami = import 'github.com/metio/kurly/workloads/umami/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='umami-db', database='umami')).items,
  kurly.list(umami()).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `umami` | |
| `image` | `ghcr.io/umami-software/umami:postgresql-v2.15.1` | the PostgreSQL image variant |
| `secretName` | `umami-secrets` | Secret with `DATABASE_URL` and `APP_SECRET` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the dashboard and tracking API on `:3000` — compose an exposure onto it.

## Database and secrets

Umami reads `DATABASE_URL` (with the database password embedded) and `APP_SECRET`
from the environment. kurly authors **no Secret** — provide `umami-secrets` holding
both, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `umami-db`. Being stateless, it can run several
replicas.

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
metadata: { name: kurly, namespace: umami }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-umami, namespace: umami }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/umami, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: umami }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-umami, namespace: umami }
spec: { sourceRef: { kind: OCIRepository, name: kurly-umami } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: umami, namespace: umami }
spec:
  serviceAccountName: umami-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/umami/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-umami, importPath: github.com/metio/kurly/workloads/umami }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: umami, namespace: umami }
spec:
  serviceAccountName: umami-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: umami
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: umami }
```

<!-- END generated: jaas-deploy -->
