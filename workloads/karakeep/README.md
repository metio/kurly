<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# karakeep

[Karakeep](https://karakeep.app) (formerly Hoarder) — a self-hosted "bookmark
everything" app: save links, notes and images and search them with AI tagging. A plain
composable `kurly.http` workload on the official image; its SQLite database and stored
assets live on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local karakeep = import 'github.com/metio/kurly/workloads/karakeep/server.libsonnet';

kurly.list(karakeep(nextauthUrl='https://bookmarks.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `karakeep` | |
| `image` | `ghcr.io/karakeep-app/karakeep:v0.32.0` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | database and assets (`/data`) |
| `nextauthUrl` | inferred | the public URL |
| `meiliAddr` | `http://meilisearch:7700` | Meilisearch endpoint |
| `browserWebUrl` | `http://chrome:9222` | headless-Chrome endpoint |
| `secretName` | `karakeep-secrets` | `NEXTAUTH_SECRET`, `MEILI_MASTER_KEY`, AI provider keys (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves on `:3000` — compose an exposure onto it.

## Companions

Karakeep expects two side services it does not bundle here — a **Meilisearch** instance
for full-text search (`MEILI_ADDR` + `MEILI_MASTER_KEY`) and a **headless Chrome** for
fetching page content (`BROWSER_WEB_URL`). Run them alongside and point the env at them;
the web app starts without them, but search and crawling stay degraded until they are
reachable.

## Persistence

The SQLite database and assets live on a ReadWriteOnce volume, so this is **one replica,
recreated**.

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
metadata: { name: kurly, namespace: karakeep }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-karakeep, namespace: karakeep }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/karakeep, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: karakeep }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-karakeep, namespace: karakeep }
spec: { sourceRef: { kind: OCIRepository, name: kurly-karakeep } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: karakeep, namespace: karakeep }
spec:
  serviceAccountName: karakeep-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/karakeep/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-karakeep, importPath: github.com/metio/kurly/workloads/karakeep }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: karakeep, namespace: karakeep }
spec:
  serviceAccountName: karakeep-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: karakeep
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: karakeep }
```

<!-- END generated: jaas-deploy -->
