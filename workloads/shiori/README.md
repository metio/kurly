<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# shiori

[Shiori](https://github.com/go-shiori/shiori) — a simple, self-hosted bookmarks
manager with web-page archiving. A plain composable `kurly.http` workload that keeps
its bookmarks and archived pages in SQLite on a PersistentVolume, so it needs no
external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local shiori = import 'github.com/metio/kurly/workloads/shiori/server.libsonnet';

kurly.list(shiori())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `shiori` | |
| `image` | `ghcr.io/go-shiori/shiori:v1.8.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | database and archives (`/shiori`) |
| `env` | `{}` | extra `SHIORI_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:8080` — compose an exposure onto it. Point
`SHIORI_DATABASE_URL` at an external PostgreSQL/MySQL through `env` to scale past the
single SQLite writer.

## Persistence

The SQLite database and archives live on a ReadWriteOnce volume, so this is **one
replica, recreated** — the same single-writer discipline as
[vaultwarden](../vaultwarden/).

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
metadata: { name: kurly, namespace: shiori }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-shiori, namespace: shiori }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/shiori, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: shiori }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-shiori, namespace: shiori }
spec: { sourceRef: { kind: OCIRepository, name: kurly-shiori } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: shiori, namespace: shiori }
spec:
  serviceAccountName: shiori-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/shiori/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-shiori, importPath: github.com/metio/kurly/workloads/shiori }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: shiori, namespace: shiori }
spec:
  serviceAccountName: shiori-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: shiori
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: shiori }
```

<!-- END generated: jaas-deploy -->
