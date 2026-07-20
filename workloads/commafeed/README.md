<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# commafeed

[CommaFeed](https://github.com/Athou/commafeed) — a self-hosted Google Reader-style
RSS/Atom feed reader. A plain composable `kurly.http` workload on the official image:
the H2 variant keeps its feeds and articles in an embedded database on a
PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local commafeed = import 'github.com/metio/kurly/workloads/commafeed/server.libsonnet';

kurly.list(commafeed())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `commafeed` | |
| `image` | `docker.io/athou/commafeed:7.2.0-h2` | the H2 (embedded-DB) variant |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the embedded database (`/commafeed/data`) |
| `env` | `{}` | extra `CF_APP_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:8082` — compose an exposure onto it.

## Persistence

The embedded H2 database lives on a ReadWriteOnce volume, so this is **one replica,
recreated** — the same single-writer discipline as [vaultwarden](../vaultwarden/). Use
the PostgreSQL image variant (`athou/commafeed:<version>-postgresql`) and point
`CF_APP_DATABASE` at a [cnpg-cluster](../cnpg-cluster/) to scale past the embedded DB.

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
metadata: { name: kurly, namespace: commafeed }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-commafeed, namespace: commafeed }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/commafeed, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: commafeed }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-commafeed, namespace: commafeed }
spec: { sourceRef: { kind: OCIRepository, name: kurly-commafeed } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: commafeed, namespace: commafeed }
spec:
  serviceAccountName: commafeed-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/commafeed/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-commafeed, importPath: github.com/metio/kurly/workloads/commafeed }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: commafeed, namespace: commafeed }
spec:
  serviceAccountName: commafeed-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: commafeed
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: commafeed }
```

<!-- END generated: jaas-deploy -->
