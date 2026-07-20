<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wekan

[Wekan](https://wekan.github.io) — a self-hosted, open-source kanban board, à la
Trello. A plain composable `kurly.http` workload on the official image, backed by an
external MongoDB.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wekan = import 'github.com/metio/kurly/workloads/wekan/server.libsonnet';

kurly.list(wekan(rootUrl='https://boards.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wekan` | |
| `image` | `docker.io/wekan/wekan:v10.03` | |
| `replicas` | `2` | stateless — scale freely |
| `rootUrl` | inferred | the public URL |
| `secretName` | `wekan-secrets` | Secret with `MONGO_URL` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves on `:8080` — compose an exposure onto it. Pairs with a
[mongodb-cluster](../mongodb-cluster/) named `wekan-db`.

## Persistence

Card attachments live in MongoDB (GridFS) by default, so this is **stateless** — a
plain rolling Deployment.

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
metadata: { name: kurly, namespace: wekan }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-wekan, namespace: wekan }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/wekan, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: wekan }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-wekan, namespace: wekan }
spec: { sourceRef: { kind: OCIRepository, name: kurly-wekan } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: wekan, namespace: wekan }
spec:
  serviceAccountName: wekan-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/wekan/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-wekan, importPath: github.com/metio/kurly/workloads/wekan }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: wekan, namespace: wekan }
spec:
  serviceAccountName: wekan-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: wekan
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: wekan }
```

<!-- END generated: jaas-deploy -->
