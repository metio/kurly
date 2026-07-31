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
| `image` | `docker.io/kanboard/kanboard:v1.2.53` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the data volume (`/var/www/app/data`) |
| `env` | `{}` | extra environment (`DATABASE_URL` for external Postgres, `PLUGIN_INSTALLER`, …) |
| `resources` / `labels` / `annotations` | | |

Serves the web UI on `:80` — compose an exposure onto it:

```jsonnet
kurly.list([
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
metadata: { name: kurly, namespace: kanboard }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-kanboard, namespace: kanboard }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/kanboard, ref: { tag: 2026.7.29 } }
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
        name: kanboard
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: kanboard }
```

<!-- END generated: jaas-deploy -->
