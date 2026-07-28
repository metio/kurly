<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# trilium

[TriliumNext Notes](https://github.com/TriliumNext/Trilium) — a hierarchical
note-taking application for building personal knowledge bases. A plain composable
`kurly.http` workload that keeps its notes in a SQLite database on a
PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local trilium = import 'github.com/metio/kurly/workloads/trilium/server.libsonnet';

kurly.list(trilium())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `trilium` | |
| `image` | `ghcr.io/triliumnext/trilium:v0.104.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the SQLite data volume (`/home/node/trilium-data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web app and sync API on `:8080` — compose an exposure onto it.

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
metadata: { name: kurly, namespace: trilium }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-trilium, namespace: trilium }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/trilium, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: trilium }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-trilium, namespace: trilium }
spec: { sourceRef: { kind: OCIRepository, name: kurly-trilium } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: trilium, namespace: trilium }
spec:
  serviceAccountName: trilium-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/trilium/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-trilium, importPath: github.com/metio/kurly/workloads/trilium }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: trilium, namespace: trilium }
spec:
  serviceAccountName: trilium-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: trilium
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: trilium }
```

<!-- END generated: jaas-deploy -->
