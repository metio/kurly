<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# stirling-pdf

[Stirling-PDF](https://github.com/Stirling-Tools/Stirling-PDF) — a locally-hosted
web toolkit for splitting, merging, converting, and editing PDFs. A plain composable
`kurly.http` workload on the official image: it processes files in memory and keeps
its configuration on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local stirling = import 'github.com/metio/kurly/workloads/stirling-pdf/server.libsonnet';

kurly.list(stirling())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `stirling-pdf` | |
| `image` | `docker.io/stirlingtools/stirling-pdf:2.14.2` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | configuration and custom files (`/configs`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:8080` — compose an exposure onto it.

## Security and persistence

The image runs LibreOffice and other tools and writes across the root filesystem, so
this workload relaxes kurly's read-only-rootfs default while keeping non-root,
dropped capabilities, and no privilege escalation. The configuration lives on a
ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: stirling-pdf }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-stirling-pdf, namespace: stirling-pdf }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/stirling-pdf, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: stirling-pdf }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-stirling-pdf, namespace: stirling-pdf }
spec: { sourceRef: { kind: OCIRepository, name: kurly-stirling-pdf } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: stirling-pdf, namespace: stirling-pdf }
spec:
  serviceAccountName: stirling-pdf-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/stirling-pdf/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-stirling-pdf, importPath: github.com/metio/kurly/workloads/stirling-pdf }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: stirling-pdf, namespace: stirling-pdf }
spec:
  serviceAccountName: stirling-pdf-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: stirling-pdf
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: stirling-pdf }
```

<!-- END generated: jaas-deploy -->
