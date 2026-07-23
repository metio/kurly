<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# shlink

[Shlink](https://shlink.io/) — a self-hosted URL shortener with a REST API and rich
analytics. A plain composable `kurly.http` workload on the official image, backed by
an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local shlink = import 'github.com/metio/kurly/workloads/shlink/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='shlink-db', database='shlink'),
  shlink(defaultDomain='s.example.com'),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `shlink` | |
| `image` | `docker.io/shlinkio/shlink:5.1.5` | |
| `dbHost` / `dbName` / `dbUser` | `shlink-db-rw` / `shlink` / `shlink` | the PostgreSQL database |
| `defaultDomain` | required | the short-URL domain |
| `secretName` | `shlink-secrets` | Secret with `DB_PASSWORD` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the short-URL routes and REST API on `:8080` — compose an exposure onto it.

## Database and secrets

Shlink reads its database coordinates from env and `DB_PASSWORD` from a provided Secret
via `envFrom`. kurly authors **no Secret** — fill `shlink-secrets` with
[`kurly.externalSecret`](../../main.libsonnet). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `shlink-db`. Its state lives in the database, so
it is stateless and can run several replicas.

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
metadata: { name: kurly, namespace: shlink }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-shlink, namespace: shlink }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/shlink, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: shlink }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-shlink, namespace: shlink }
spec: { sourceRef: { kind: OCIRepository, name: kurly-shlink } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: shlink, namespace: shlink }
spec:
  serviceAccountName: shlink-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/shlink/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-shlink, importPath: github.com/metio/kurly/workloads/shlink }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: shlink, namespace: shlink }
spec:
  serviceAccountName: shlink-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: shlink
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: shlink }
```

<!-- END generated: jaas-deploy -->
