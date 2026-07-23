<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wikijs

[Wiki.js](https://github.com/requarks/wiki) — a modern, open-source wiki. A plain
composable `kurly.http` workload on the official image, backed by an external
PostgreSQL. Its content and configuration live in the database, so the workload is
stateless and can run several replicas.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wikijs = import 'github.com/metio/kurly/workloads/wikijs/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='wikijs-db', database='wikijs'),
  wikijs(),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wikijs` | |
| `image` | `ghcr.io/requarks/wiki:2.5.314` | |
| `dbHost` / `dbName` / `dbUser` | `wikijs-db-rw` / `wikijs` / `wikijs` | the PostgreSQL database |
| `secretName` | `wikijs-secrets` | Secret with `DB_PASS` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the wiki and API on `:3000` — compose an exposure onto it.

## Database and secrets

Wiki.js reads its database coordinates from env and `DB_PASS` from a provided Secret
via `envFrom`. kurly authors **no Secret** — fill `wikijs-secrets` with
[`kurly.externalSecret`](../../main.libsonnet). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `wikijs-db`. Its content lives in the database,
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
metadata: { name: kurly, namespace: wikijs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-wikijs, namespace: wikijs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/wikijs, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: wikijs }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-wikijs, namespace: wikijs }
spec: { sourceRef: { kind: OCIRepository, name: kurly-wikijs } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: wikijs, namespace: wikijs }
spec:
  serviceAccountName: wikijs-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/wikijs/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-wikijs, importPath: github.com/metio/kurly/workloads/wikijs }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: wikijs, namespace: wikijs }
spec:
  serviceAccountName: wikijs-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: wikijs
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: wikijs }
```

<!-- END generated: jaas-deploy -->
