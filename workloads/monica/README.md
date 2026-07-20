<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# monica

[Monica](https://www.monicahq.com/) — a self-hosted personal relationship manager:
keep track of your interactions with the people who matter. A plain composable
`kurly.http` workload on the official image, backed by an external MySQL/MariaDB, with
its uploads on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local monica = import 'github.com/metio/kurly/workloads/monica/server.libsonnet';

kurly.list(monica(appUrl='https://monica.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `monica` | |
| `image` | `docker.io/library/monica:4.1.2-apache` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | uploads (`/var/www/html/storage`) |
| `dbHost` / `dbName` / `dbUser` | `monica-db` / `monica` / `monica` | the MySQL/MariaDB database |
| `appUrl` | inferred | the public URL |
| `secretName` | `monica-secrets` | Secret with `DB_PASSWORD` and `APP_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Database and secrets

Monica needs a **MySQL/MariaDB** database — the [mysql-cluster](../mysql-cluster/)
workload provides one. It reads its database coordinates from env and `DB_PASSWORD` and
`APP_KEY` from a provided Secret via `envFrom`. kurly authors **no Secret** — fill
`monica-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. Uploads live on a ReadWriteOnce volume, so this is **one
replica, recreated**.

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
metadata: { name: kurly, namespace: monica }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-monica, namespace: monica }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/monica, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: monica }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-monica, namespace: monica }
spec: { sourceRef: { kind: OCIRepository, name: kurly-monica } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: monica, namespace: monica }
spec:
  serviceAccountName: monica-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/monica/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-monica, importPath: github.com/metio/kurly/workloads/monica }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: monica, namespace: monica }
spec:
  serviceAccountName: monica-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: monica
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: monica }
```

<!-- END generated: jaas-deploy -->
