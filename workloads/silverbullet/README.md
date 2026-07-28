<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# silverbullet

[SilverBullet](https://github.com/silverbulletmd/silverbullet) — an extensible,
self-hosted markdown notebook / personal knowledge base. A plain composable
`kurly.http` workload: your notes are plain markdown files on a PersistentVolume, so
it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local silverbullet = import 'github.com/metio/kurly/workloads/silverbullet/server.libsonnet';

kurly.list(silverbullet())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `silverbullet` | |
| `image` | `ghcr.io/silverbulletmd/silverbullet:2.9.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the markdown space (`/space`) |
| `secretName` | `silverbullet-secrets` | Secret with `SB_USER` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the editor on `:3000` — compose an exposure onto it.

## Auth and persistence

SilverBullet reads `SB_USER` (`user:password`) from the environment. kurly authors
**no Secret** — provide `silverbullet-secrets` holding `SB_USER`, pulled in via
`envFrom` (fill it with [`kurly.externalSecret`](../../main.libsonnet)). The markdown
space lives on a ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: silverbullet }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-silverbullet, namespace: silverbullet }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/silverbullet, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: silverbullet }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-silverbullet, namespace: silverbullet }
spec: { sourceRef: { kind: OCIRepository, name: kurly-silverbullet } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: silverbullet, namespace: silverbullet }
spec:
  serviceAccountName: silverbullet-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/silverbullet/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-silverbullet, importPath: github.com/metio/kurly/workloads/silverbullet }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: silverbullet, namespace: silverbullet }
spec:
  serviceAccountName: silverbullet-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: silverbullet
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: silverbullet }
```

<!-- END generated: jaas-deploy -->
