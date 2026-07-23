<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# directus

[Directus](https://github.com/directus/directus) — an open-source headless CMS and
data platform over your SQL database. A plain composable `kurly.http` workload on the
official image, backed by an external PostgreSQL, with its uploads on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local directus = import 'github.com/metio/kurly/workloads/directus/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='directus-db', database='directus'),
  directus(publicUrl='https://cms.example.com'),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `directus` | |
| `image` | `docker.io/directus/directus:12.1.1` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | uploads (`/directus/uploads`) |
| `dbHost` / `dbName` / `dbUser` | `directus-db-rw` / `directus` / `directus` | the PostgreSQL database |
| `publicUrl` | inferred | the public URL |
| `adminEmail` | `admin@example.com` | the first-run admin |
| `secretName` | `directus-secrets` | Secret with `DB_PASSWORD`, `KEY`, `SECRET`, `ADMIN_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the admin app and API on `:8055` — compose an exposure onto it.

## Database and secrets

Directus reads its database coordinates from env, and `DB_PASSWORD`, `KEY`, `SECRET`,
and the first-run `ADMIN_PASSWORD` from a provided Secret via `envFrom`. kurly authors
**no Secret** — fill `directus-secrets` with
[`kurly.externalSecret`](../../main.libsonnet). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `directus-db`.

## Persistence

Uploaded files live on a ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: directus }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-directus, namespace: directus }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/directus, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: directus }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-directus, namespace: directus }
spec: { sourceRef: { kind: OCIRepository, name: kurly-directus } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: directus, namespace: directus }
spec:
  serviceAccountName: directus-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/directus/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-directus, importPath: github.com/metio/kurly/workloads/directus }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: directus, namespace: directus }
spec:
  serviceAccountName: directus-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: directus
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: directus }
```

<!-- END generated: jaas-deploy -->
