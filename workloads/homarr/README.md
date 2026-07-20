<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# homarr

[Homarr](https://homarr.dev) — a sleek, self-hosted dashboard for your homelab: pin
your services, search across them, and watch their status in one place. A plain
composable `kurly.http` workload on the official image; its SQLite database and config
live on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local homarr = import 'github.com/metio/kurly/workloads/homarr/server.libsonnet';

kurly.list(homarr())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `homarr` | |
| `image` | `ghcr.io/homarr-labs/homarr:v1.71.0` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | data (`/appdata`) |
| `secretName` | `homarr-secrets` | Secret with `SECRET_ENCRYPTION_KEY` (64-char hex, envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the dashboard on `:7575` — compose an exposure onto it.

## Persistence

The SQLite database lives on a ReadWriteOnce volume, so this is **one replica,
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
metadata: { name: kurly, namespace: homarr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-homarr, namespace: homarr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/homarr, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: homarr }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-homarr, namespace: homarr }
spec: { sourceRef: { kind: OCIRepository, name: kurly-homarr } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: homarr, namespace: homarr }
spec:
  serviceAccountName: homarr-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/homarr/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-homarr, importPath: github.com/metio/kurly/workloads/homarr }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: homarr, namespace: homarr }
spec:
  serviceAccountName: homarr-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: homarr
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: homarr }
```

<!-- END generated: jaas-deploy -->
