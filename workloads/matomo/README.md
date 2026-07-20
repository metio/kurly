<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# matomo

[Matomo](https://matomo.org/) — a privacy-focused, self-hosted web-analytics platform,
the open-source Google Analytics alternative. A plain composable `kurly.http` workload
on the official image, backed by an external MySQL/MariaDB, with its config and plugins
on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local matomo = import 'github.com/metio/kurly/workloads/matomo/server.libsonnet';

kurly.list(matomo())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `matomo` | |
| `image` | `docker.io/library/matomo:5.12.0-apache` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | config and plugins (`/var/www/html`) |
| `dbHost` / `dbName` / `dbUser` | `matomo-db` / `matomo` / `matomo` | the MySQL/MariaDB database |
| `secretName` | `matomo-secrets` | Secret with `MATOMO_DATABASE_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and tracking API on `:80` — compose an exposure onto it.

## Database and secrets

Matomo needs a **MySQL/MariaDB** database — the [mysql-cluster](../mysql-cluster/)
workload provides one. It reads its database coordinates from env and
`MATOMO_DATABASE_PASSWORD` from a provided Secret via `envFrom`. kurly authors **no
Secret** — fill `matomo-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. Config and plugins live on a ReadWriteOnce volume, so this is
**one replica, recreated**.

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
metadata: { name: kurly, namespace: matomo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-matomo, namespace: matomo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/matomo, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: matomo }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-matomo, namespace: matomo }
spec: { sourceRef: { kind: OCIRepository, name: kurly-matomo } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: matomo, namespace: matomo }
spec:
  serviceAccountName: matomo-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/matomo/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-matomo, importPath: github.com/metio/kurly/workloads/matomo }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: matomo, namespace: matomo }
spec:
  serviceAccountName: matomo-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: matomo
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: matomo }
```

<!-- END generated: jaas-deploy -->
