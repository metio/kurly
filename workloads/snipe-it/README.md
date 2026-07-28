<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# snipe-it

[Snipe-IT](https://github.com/snipe/snipe-it) — a free, open-source IT asset and
license management system. A plain composable `kurly.http` workload on the official
image, backed by an external MySQL/MariaDB, with its uploads on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local snipeit = import 'github.com/metio/kurly/workloads/snipe-it/server.libsonnet';

kurly.list(snipeit(appUrl='https://assets.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `snipe-it` | |
| `image` | `docker.io/snipe/snipe-it:v8.6.3` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | uploads (`/var/lib/snipeit`) |
| `dbHost` / `dbName` / `dbUser` | `snipe-it-db` / `snipeit` / `snipeit` | the MySQL/MariaDB database |
| `appUrl` | inferred | the public URL |
| `secretName` | `snipe-it-secrets` | Secret with `DB_PASSWORD` and `APP_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:80` — compose an exposure onto it.

## Database and secrets

Snipe-IT needs a **MySQL/MariaDB** database — the [mysql-cluster](../mysql-cluster/)
workload provides one. It reads its database coordinates from env and `DB_PASSWORD` and
`APP_KEY` from a provided Secret via `envFrom`. kurly authors **no Secret** — fill
`snipe-it-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

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
metadata: { name: kurly, namespace: snipe-it }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-snipe-it, namespace: snipe-it }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/snipe-it, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: snipe-it }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-snipe-it, namespace: snipe-it }
spec: { sourceRef: { kind: OCIRepository, name: kurly-snipe-it } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: snipe-it, namespace: snipe-it }
spec:
  serviceAccountName: snipe-it-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/snipe-it/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-snipe-it, importPath: github.com/metio/kurly/workloads/snipe-it }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: snipe-it, namespace: snipe-it }
spec:
  serviceAccountName: snipe-it-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: snipe-it
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: snipe-it }
```

<!-- END generated: jaas-deploy -->
