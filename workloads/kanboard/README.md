<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# kanboard

[Kanboard](https://kanboard.org/) — a minimalist kanban project-management board. A
plain composable `kurly.http` workload on the official image that keeps its board
data in a SQLite database and uploaded files on a PersistentVolume by default, so
it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local kanboard = import 'github.com/metio/kurly/workloads/kanboard/server.libsonnet';

kurly.list(kanboard())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `kanboard` | |
| `image` | `docker.io/kanboard/kanboard:v1.2.52` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the data volume (`/var/www/app/data`) |
| `env` | `{}` | extra environment (`DATABASE_URL` for external Postgres, `PLUGIN_INSTALLER`, …) |
| `resources` / `labels` / `annotations` | | |

Serves the web UI on `:80` — compose an exposure onto it:

```jsonnet
kurly.listOf([
  kanboard()
  + kurly.expose.ownGateway('board.example.com', 'istio', tls='kanboard-tls'),
  kurly.certificate('kanboard-tls', ['board.example.com'], 'letsencrypt-prod'),
])
```

Point `DATABASE_URL` at an external PostgreSQL (the [cnpg-cluster](../cnpg-cluster/)
workload) to scale past the single SQLite writer.

## Security and persistence

The nginx + PHP-FPM image starts as **root** and binds `:80`, so this workload
relaxes kurly's non-root and read-only-rootfs defaults while keeping dropped
capabilities and no privilege escalation. The SQLite database lives on a
ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: kanboard }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-kanboard, namespace: kanboard }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/kanboard, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: kanboard }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-kanboard, namespace: kanboard }
spec: { sourceRef: { kind: OCIRepository, name: kurly-kanboard } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: kanboard, namespace: kanboard }
spec:
  serviceAccountName: kanboard-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/kanboard/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-kanboard, importPath: github.com/metio/kurly/workloads/kanboard }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: kanboard, namespace: kanboard }
spec:
  serviceAccountName: kanboard-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: kanboard
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: kanboard }
```

<!-- END generated: jaas-deploy -->
