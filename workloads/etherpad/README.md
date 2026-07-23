<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# etherpad

[Etherpad](https://etherpad.org/) — a real-time collaborative document editor. A
plain composable `kurly.http` workload on the official image, backed by an external
PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local etherpad = import 'github.com/metio/kurly/workloads/etherpad/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='etherpad-db', database='etherpad'),
  etherpad(),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `etherpad` | |
| `image` | `docker.io/etherpad/etherpad:3.3.2` | |
| `dbHost` / `dbName` / `dbUser` | `etherpad-db-rw` / `etherpad` / `etherpad` | the PostgreSQL database |
| `secretName` | `etherpad-secrets` | Secret with `DB_PASS`, `ADMIN_PASSWORD`, `APIKEY` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the editor and API on `:9001` — compose an exposure onto it.

## Database and secrets

Etherpad reads its database coordinates and `DB_PASS`, plus `ADMIN_PASSWORD` and
`APIKEY`, from the environment. The non-secret coordinates default to a
[cnpg-cluster](../cnpg-cluster/) named `etherpad-db`; the secrets come from a provided
Secret via `envFrom`. kurly authors **no Secret** — fill `etherpad-secrets` with
[`kurly.externalSecret`](../../main.libsonnet). Its documents live in the database, so
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
metadata: { name: kurly, namespace: etherpad }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-etherpad, namespace: etherpad }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/etherpad, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: etherpad }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-etherpad, namespace: etherpad }
spec: { sourceRef: { kind: OCIRepository, name: kurly-etherpad } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: etherpad, namespace: etherpad }
spec:
  serviceAccountName: etherpad-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/etherpad/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-etherpad, importPath: github.com/metio/kurly/workloads/etherpad }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: etherpad, namespace: etherpad }
spec:
  serviceAccountName: etherpad-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: etherpad
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: etherpad }
```

<!-- END generated: jaas-deploy -->
