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

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage. Delivered end to end through Flux, JaaS and stageset-controller on 2026-08-02, and observed rolling out.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: excalidraw }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-excalidraw, namespace: excalidraw }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/excalidraw, ref: { tag: 2026.7.29 } }
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
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
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
