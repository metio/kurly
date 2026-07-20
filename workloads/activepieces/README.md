<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# activepieces

[Activepieces](https://www.activepieces.com) — a self-hosted, open-source no-code
automation / workflow builder, à la Zapier. A plain composable `kurly.http` workload on
the official all-in-one image, backed by an external PostgreSQL and Redis.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local activepieces = import 'github.com/metio/kurly/workloads/activepieces/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='activepieces-db', database='activepieces')).items,
  kurly.list(activepieces(frontendUrl='https://flows.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `activepieces` | |
| `image` | `docker.io/activepieces/activepieces:0.86.3` | |
| `replicas` | `2` | stateless — scale freely |
| `frontendUrl` | inferred | the public URL (webhook URLs derive from it) |
| `secretName` | `activepieces-secrets` | `AP_POSTGRES_*`, `AP_REDIS_*`, `AP_ENCRYPTION_KEY`, `AP_JWT_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves on `:80` — compose an exposure onto it.

## Persistence

Flow state lives in PostgreSQL and Redis, so this is **stateless** — a plain rolling
Deployment.

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
metadata: { name: kurly, namespace: activepieces }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-activepieces, namespace: activepieces }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/activepieces, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: activepieces }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-activepieces, namespace: activepieces }
spec: { sourceRef: { kind: OCIRepository, name: kurly-activepieces } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: activepieces, namespace: activepieces }
spec:
  serviceAccountName: activepieces-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/activepieces/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-activepieces, importPath: github.com/metio/kurly/workloads/activepieces }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: activepieces, namespace: activepieces }
spec:
  serviceAccountName: activepieces-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: activepieces
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: activepieces }
```

<!-- END generated: jaas-deploy -->
