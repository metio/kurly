<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# excalidraw

[Excalidraw](https://github.com/excalidraw/excalidraw) — a virtual hand-drawn-style
whiteboard. A plain composable `kurly.http` workload on the official image.
Excalidraw is a client-side app: the container just serves the static assets and
drawings live in the browser, so this workload is **stateless** and can run several
replicas.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local excalidraw = import 'github.com/metio/kurly/workloads/excalidraw/server.libsonnet';

kurly.list(excalidraw())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `excalidraw` | |
| `image` | `docker.io/excalidraw/excalidraw:sha-4bfc5bb` | immutable sha tag (no semver published) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the app on `:80` — compose an exposure onto it.

## Security

The nginx image serving the static assets starts as **root** and binds `:80`, so
this workload relaxes kurly's non-root and read-only-rootfs defaults while keeping
dropped capabilities and no privilege escalation.

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
metadata: { name: kurly, namespace: excalidraw }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-excalidraw, namespace: excalidraw }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/excalidraw, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: excalidraw }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-excalidraw, namespace: excalidraw }
spec: { sourceRef: { kind: OCIRepository, name: kurly-excalidraw } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: excalidraw, namespace: excalidraw }
spec:
  serviceAccountName: excalidraw-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/excalidraw/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-excalidraw, importPath: github.com/metio/kurly/workloads/excalidraw }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: excalidraw, namespace: excalidraw }
spec:
  serviceAccountName: excalidraw-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: excalidraw
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: excalidraw }
```

<!-- END generated: jaas-deploy -->
