<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ghost

[Ghost](https://ghost.org/) — a modern, open-source publishing and newsletter
platform. A plain composable `kurly.http` workload on the official image, backed by an
external MySQL/MariaDB, with its content (themes, images, uploads) on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ghost = import 'github.com/metio/kurly/workloads/ghost/server.libsonnet';

kurly.list(ghost(url='https://blog.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `ghost` | |
| `image` | `docker.io/library/ghost:5.130.6-alpine` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | content (`/var/lib/ghost/content`) |
| `dbHost` / `dbName` / `dbUser` | `ghost-db` / `ghost` / `ghost` | the MySQL/MariaDB database |
| `url` | inferred | the public URL |
| `secretName` | `ghost-secrets` | Secret with the DB password (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the site and admin on `:2368` — compose an exposure onto it.

## Database and secrets

Ghost needs a **MySQL/MariaDB** database — the [mysql-cluster](../mysql-cluster/)
workload provides one. It reads its database coordinates from env and the database
password from a provided Secret via `envFrom`. kurly authors **no Secret** — fill
`ghost-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

## Persistence

The content lives on a ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: ghost }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-ghost, namespace: ghost }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/ghost, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: ghost }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-ghost, namespace: ghost }
spec: { sourceRef: { kind: OCIRepository, name: kurly-ghost } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ghost, namespace: ghost }
spec:
  serviceAccountName: ghost-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/ghost/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-ghost, importPath: github.com/metio/kurly/workloads/ghost }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: ghost, namespace: ghost }
spec:
  serviceAccountName: ghost-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: ghost
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: ghost }
```

<!-- END generated: jaas-deploy -->
