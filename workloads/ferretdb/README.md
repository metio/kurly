<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ferretdb

[FerretDB](https://www.ferretdb.com/) — an open-source, MongoDB-compatible database.
It is a **stateless** proxy that speaks the MongoDB wire protocol and stores
everything in a PostgreSQL backend (with the DocumentDB extension), so this workload
needs no volume of its own and can run several replicas.

**Why FerretDB:** it is **Apache-2.0** and MongoDB-wire-compatible — the permissive
alternative to MongoDB Community (SSPL) for a platform that monetizes hosting. See
[mongodb-cluster](../mongodb-cluster/) for the SSPL engine.

## Compose

FerretDB v2 needs a PostgreSQL with the **DocumentDB extension**. Run one with
[cnpg-cluster](../cnpg-cluster/) pinned to the FerretDB image, then point FerretDB at
it:

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ferretdb = import 'github.com/metio/kurly/workloads/ferretdb/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='ferretdb-db', imageName='ghcr.io/ferretdb/postgres-documentdb:17'),
  ferretdb(),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `ferretdb` | |
| `image` | `ghcr.io/ferretdb/ferretdb:2.7.0` | the proxy image |
| `secretName` | `ferretdb-secrets` | Secret with `FERRETDB_POSTGRESQL_URL` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the MongoDB wire protocol on `:27017` — route it as TCP for MongoDB clients.

## Backend and secrets

kurly authors **no Secret** — provide `ferretdb-secrets` holding
`FERRETDB_POSTGRESQL_URL` (with the backend password), pulled in via `envFrom` (fill
it with [`kurly.externalSecret`](../../main.libsonnet)). The backend is a PostgreSQL
with the DocumentDB extension; the `ghcr.io/ferretdb/postgres-documentdb` image
provides it, run through `cnpg-cluster`.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: ferretdb }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-ferretdb, namespace: ferretdb }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/ferretdb, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: ferretdb }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-ferretdb, namespace: ferretdb }
spec: { sourceRef: { kind: OCIRepository, name: kurly-ferretdb } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ferretdb, namespace: ferretdb }
spec:
  serviceAccountName: ferretdb-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/ferretdb/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-ferretdb, importPath: github.com/metio/kurly/workloads/ferretdb }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: ferretdb, namespace: ferretdb }
spec:
  serviceAccountName: ferretdb-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: ferretdb
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: ferretdb }
```

<!-- END generated: jaas-deploy -->
