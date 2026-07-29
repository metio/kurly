<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# listmonk

[listmonk](https://github.com/knadh/listmonk) — a self-hosted newsletter and
mailing-list manager. A plain composable `kurly.http` workload on the official image,
backed by an external PostgreSQL, with its uploaded media on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local listmonk = import 'github.com/metio/kurly/workloads/listmonk/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='listmonk-db', database='listmonk'),
  listmonk(),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `listmonk` | |
| `image` | `docker.io/listmonk/listmonk:v6.2.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | uploaded media (`/listmonk/uploads`) |
| `dbHost` / `dbName` / `dbUser` | `listmonk-db-rw` / `listmonk` / `listmonk` | the PostgreSQL database |
| `adminUser` | `admin` | the admin username |
| `secretName` | `listmonk-secrets` | Secret with `LISTMONK_db__password` and `LISTMONK_app__admin_password` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the admin UI and API on `:9000` — compose an exposure onto it.

## Database and secrets

listmonk reads its database and admin coordinates from the environment. The non-secret
coordinates default to a [cnpg-cluster](../cnpg-cluster/) named `listmonk-db`; the
passwords come from a provided Secret via `envFrom`. kurly authors **no Secret** — fill
`listmonk-secrets` with [`kurly.externalSecret`](../../main.libsonnet). Run the
one-time schema install (`./listmonk --install`) against the database before first use.

## Persistence

Uploaded media lives on a ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: listmonk }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-listmonk, namespace: listmonk }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/listmonk, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: listmonk }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-listmonk, namespace: listmonk }
spec: { sourceRef: { kind: OCIRepository, name: kurly-listmonk } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: listmonk, namespace: listmonk }
spec:
  serviceAccountName: listmonk-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/listmonk/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-listmonk, importPath: github.com/metio/kurly/workloads/listmonk }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: listmonk, namespace: listmonk }
spec:
  serviceAccountName: listmonk-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: listmonk
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: listmonk }
```

<!-- END generated: jaas-deploy -->
