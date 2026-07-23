<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# firefly-iii

[Firefly III](https://github.com/firefly-iii/firefly-iii) — a free, self-hosted
personal-finance manager. A plain composable `kurly.http` workload on the official
image, backed by an external PostgreSQL, with its uploads on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local firefly = import 'github.com/metio/kurly/workloads/firefly-iii/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='firefly-iii-db', database='firefly'),
  firefly(appUrl='https://finance.example.com'),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `firefly-iii` | |
| `image` | `docker.io/fireflyiii/core:version-6.6.6` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | uploads |
| `dbHost` / `dbName` / `dbUser` | `firefly-iii-db-rw` / `firefly` / `firefly` | the PostgreSQL database |
| `appUrl` | inferred | the public URL |
| `secretName` | `firefly-iii-secrets` | Secret with `DB_PASSWORD` and `APP_KEY` (32-char, envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:8080` — compose an exposure onto it.

## Database and secrets

Firefly III reads its database coordinates from env and `DB_PASSWORD` and `APP_KEY`
from a provided Secret via `envFrom`. kurly authors **no Secret** — fill
`firefly-iii-secrets` with [`kurly.externalSecret`](../../main.libsonnet). The defaults
pair with a [cnpg-cluster](../cnpg-cluster/) named `firefly-iii-db`.

## Security and persistence

The Apache + PHP image starts as **root** and binds `:8080`, so this workload relaxes
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
metadata: { name: kurly, namespace: firefly-iii }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-firefly-iii, namespace: firefly-iii }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/firefly-iii, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: firefly-iii }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-firefly-iii, namespace: firefly-iii }
spec: { sourceRef: { kind: OCIRepository, name: kurly-firefly-iii } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: firefly-iii, namespace: firefly-iii }
spec:
  serviceAccountName: firefly-iii-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/firefly-iii/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-firefly-iii, importPath: github.com/metio/kurly/workloads/firefly-iii }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: firefly-iii, namespace: firefly-iii }
spec:
  serviceAccountName: firefly-iii-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: firefly-iii
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: firefly-iii }
```

<!-- END generated: jaas-deploy -->
