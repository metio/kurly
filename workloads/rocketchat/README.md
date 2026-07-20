<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# rocketchat

[Rocket.Chat](https://rocket.chat) — a self-hosted, open-source team chat and
collaboration platform. A plain composable `kurly.http` workload on the official image,
backed by an external MongoDB **replica set** (Rocket.Chat requires the oplog).

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local rocketchat = import 'github.com/metio/kurly/workloads/rocketchat/server.libsonnet';

kurly.list(rocketchat(rootUrl='https://chat.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `rocketchat` | |
| `image` | `docker.io/rocketchat/rocket.chat:8.6.1` | |
| `replicas` | `2` | stateless — scale freely |
| `rootUrl` | inferred | the public URL |
| `secretName` | `rocketchat-secrets` | Secret with `MONGO_URL` and `MONGO_OPLOG_URL` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves on `:3000` — compose an exposure onto it. Pairs with a
[mongodb-cluster](../mongodb-cluster/) named `rocketchat-db`.

## Persistence

Uploaded files live in MongoDB (GridFS) by default, so this is **stateless** — a plain
rolling Deployment.

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
metadata: { name: kurly, namespace: rocketchat }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-rocketchat, namespace: rocketchat }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/rocketchat, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: rocketchat }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-rocketchat, namespace: rocketchat }
spec: { sourceRef: { kind: OCIRepository, name: kurly-rocketchat } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: rocketchat, namespace: rocketchat }
spec:
  serviceAccountName: rocketchat-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/rocketchat/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-rocketchat, importPath: github.com/metio/kurly/workloads/rocketchat }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: rocketchat, namespace: rocketchat }
spec:
  serviceAccountName: rocketchat-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: rocketchat
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: rocketchat }
```

<!-- END generated: jaas-deploy -->
