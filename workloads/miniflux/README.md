<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# miniflux

[Miniflux](https://github.com/miniflux/v2) — a minimalist, opinionated RSS/Atom feed
reader. A plain composable `kurly.http` workload on the official image, backed by an
external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local miniflux = import 'github.com/metio/kurly/workloads/miniflux/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='miniflux-db', database='miniflux')).items,
  kurly.list(miniflux()).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `miniflux` | |
| `image` | `docker.io/miniflux/miniflux:2.3.2` | |
| `secretName` | `miniflux-secrets` | Secret with `DATABASE_URL` and `ADMIN_PASSWORD` (envFrom) |
| `adminUser` | `admin` | the first-run admin username |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:8080` — compose an exposure onto it.

## Database and secrets

Miniflux reads `DATABASE_URL` (with the database password embedded) and the first-run
admin password from the environment. kurly authors **no Secret** — provide
`miniflux-secrets` holding `DATABASE_URL` and `ADMIN_PASSWORD`, pulled in via
`envFrom` (fill it with [`kurly.externalSecret`](../../main.libsonnet)). The defaults
pair with a [cnpg-cluster](../cnpg-cluster/) named `miniflux-db`. Being stateless, it
can run several replicas.

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
metadata: { name: kurly, namespace: miniflux }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-miniflux, namespace: miniflux }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/miniflux, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: miniflux }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-miniflux, namespace: miniflux }
spec: { sourceRef: { kind: OCIRepository, name: kurly-miniflux } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: miniflux, namespace: miniflux }
spec:
  serviceAccountName: miniflux-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/miniflux/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-miniflux, importPath: github.com/metio/kurly/workloads/miniflux }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: miniflux, namespace: miniflux }
spec:
  serviceAccountName: miniflux-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: miniflux
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: miniflux }
```

<!-- END generated: jaas-deploy -->
