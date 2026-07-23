<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# metabase

[Metabase](https://github.com/metabase/metabase) — an open-source business-intelligence
and analytics tool. A plain composable `kurly.http` workload on the official image,
backed by an external PostgreSQL for its application database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local metabase = import 'github.com/metio/kurly/workloads/metabase/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='metabase-db', database='metabase'),
  metabase(),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `metabase` | |
| `image` | `docker.io/metabase/metabase:v0.62.5` | |
| `dbHost` / `dbName` / `dbUser` | `metabase-db-rw` / `metabase` / `metabase` | the application database |
| `secretName` | `metabase-secrets` | Secret with `MB_DB_PASS` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:3000` — compose an exposure onto it.

## Database and secrets

Metabase reads its application-database coordinates from env and `MB_DB_PASS` from a
provided Secret via `envFrom`. kurly authors **no Secret** — fill `metabase-secrets`
with [`kurly.externalSecret`](../../main.libsonnet). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `metabase-db`. Its state lives in the database,
so it is stateless and can run several replicas.

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
metadata: { name: kurly, namespace: metabase }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-metabase, namespace: metabase }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/metabase, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: metabase }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-metabase, namespace: metabase }
spec: { sourceRef: { kind: OCIRepository, name: kurly-metabase } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: metabase, namespace: metabase }
spec:
  serviceAccountName: metabase-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/metabase/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-metabase, importPath: github.com/metio/kurly/workloads/metabase }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: metabase, namespace: metabase }
spec:
  serviceAccountName: metabase-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: metabase
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: metabase }
```

<!-- END generated: jaas-deploy -->
