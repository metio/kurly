<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# memos

[Memos](https://github.com/usememos/memos) — a lightweight, self-hosted notes and
micro-blogging service. A plain composable `kurly.http` workload that keeps its
notes in a SQLite database on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local memos = import 'github.com/metio/kurly/workloads/memos/server.libsonnet';

kurly.list(memos())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `memos` | |
| `image` | `docker.io/neosmemo/memos:0.29.1` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the SQLite data volume (`/var/opt/memos`) |
| `env` | `{}` | extra `MEMOS_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:5230` — compose an exposure onto it. Point
`MEMOS_DRIVER` at an external PostgreSQL through `env` to scale past the single
SQLite writer.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica, recreated**
— the same single-writer discipline as [vaultwarden](../vaultwarden/).

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
metadata: { name: kurly, namespace: memos }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-memos, namespace: memos }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/memos, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: memos }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-memos, namespace: memos }
spec: { sourceRef: { kind: OCIRepository, name: kurly-memos } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: memos, namespace: memos }
spec:
  serviceAccountName: memos-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/memos/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-memos, importPath: github.com/metio/kurly/workloads/memos }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: memos, namespace: memos }
spec:
  serviceAccountName: memos-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: memos
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: memos }
```

<!-- END generated: jaas-deploy -->
