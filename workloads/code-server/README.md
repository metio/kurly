<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# code-server

[code-server](https://github.com/coder/code-server) — VS Code running in the
browser, on a remote server. A plain composable `kurly.http` workload on the
official image: your projects, extensions, and settings live on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local codeServer = import 'github.com/metio/kurly/workloads/code-server/server.libsonnet';

kurly.list(codeServer())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `code-server` | |
| `image` | `docker.io/codercom/code-server:4.129.0` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | workspace, extensions, settings (`/home/coder`) |
| `secretName` | `code-server-secrets` | Secret with `PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the editor on `:8080` — compose an exposure onto it.

## Auth and persistence

code-server reads its `PASSWORD` (or `HASHED_PASSWORD`) from the environment. kurly
authors **no Secret** — provide `code-server-secrets` holding `PASSWORD`, pulled in
via `envFrom` (fill it with [`kurly.externalSecret`](../../main.libsonnet)). Your
workspace lives on a ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: code-server }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-code-server, namespace: code-server }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/code-server, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: code-server }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-code-server, namespace: code-server }
spec: { sourceRef: { kind: OCIRepository, name: kurly-code-server } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: code-server, namespace: code-server }
spec:
  serviceAccountName: code-server-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/code-server/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-code-server, importPath: github.com/metio/kurly/workloads/code-server }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: code-server, namespace: code-server }
spec:
  serviceAccountName: code-server-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: code-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: code-server }
```

<!-- END generated: jaas-deploy -->
