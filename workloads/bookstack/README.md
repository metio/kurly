<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# bookstack

[BookStack](https://www.bookstackapp.com/) — a simple, self-hosted platform for
organising and storing documentation. A plain composable `kurly.http` workload on the
maintained [LinuxServer](https://docs.linuxserver.io/images/docker-bookstack/) image,
backed by an external MySQL/MariaDB, with its config and uploads on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local bookstack = import 'github.com/metio/kurly/workloads/bookstack/server.libsonnet';

kurly.list(bookstack(appUrl='https://docs.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `bookstack` | |
| `image` | `lscr.io/linuxserver/bookstack:26.05.2` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | config and uploads (`/config`) |
| `dbHost` / `dbName` / `dbUser` | `bookstack-db` / `bookstack` / `bookstack` | the MySQL/MariaDB database |
| `appUrl` | inferred | the public URL |
| `secretName` | `bookstack-secrets` | Secret with `DB_PASS` and `APP_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Database and secrets

BookStack needs a **MySQL/MariaDB** database — the [mysql-cluster](../mysql-cluster/)
workload provides one. It reads its database coordinates from env and `DB_PASS` and
`APP_KEY` from a provided Secret via `envFrom`. kurly authors **no Secret** — fill
`bookstack-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The LinuxServer image runs its s6 init as **root** and binds `:80`, so this workload
relaxes kurly's non-root and read-only-rootfs defaults while keeping dropped
capabilities and no privilege escalation. Config and uploads live on a ReadWriteOnce
volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: bookstack }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-bookstack, namespace: bookstack }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/bookstack, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: bookstack }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-bookstack, namespace: bookstack }
spec: { sourceRef: { kind: OCIRepository, name: kurly-bookstack } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: bookstack, namespace: bookstack }
spec:
  serviceAccountName: bookstack-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/bookstack/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-bookstack, importPath: github.com/metio/kurly/workloads/bookstack }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: bookstack, namespace: bookstack }
spec:
  serviceAccountName: bookstack-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: bookstack
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: bookstack }
```

<!-- END generated: jaas-deploy -->
