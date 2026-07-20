<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gotify

[Gotify](https://gotify.net/) — a simple server for sending and receiving push
notifications. A plain composable `kurly.http` workload that keeps its messages,
apps, and clients in a SQLite database on a PersistentVolume, so it needs no
external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gotify = import 'github.com/metio/kurly/workloads/gotify/server.libsonnet';

kurly.list(gotify())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `gotify` | |
| `image` | `docker.io/gotify/server:3.0.0` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the SQLite data volume (`/app/data`) |
| `env` | `{}` | extra `GOTIFY_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:80` — compose an exposure onto it.

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
metadata: { name: kurly, namespace: gotify }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-gotify, namespace: gotify }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/gotify, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: gotify }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-gotify, namespace: gotify }
spec: { sourceRef: { kind: OCIRepository, name: kurly-gotify } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: gotify, namespace: gotify }
spec:
  serviceAccountName: gotify-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/gotify/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-gotify, importPath: github.com/metio/kurly/workloads/gotify }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: gotify, namespace: gotify }
spec:
  serviceAccountName: gotify-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: gotify
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: gotify }
```

<!-- END generated: jaas-deploy -->
