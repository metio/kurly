<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# audiobookshelf

[Audiobookshelf](https://github.com/advplyr/audiobookshelf) — a self-hosted
audiobook and podcast server. A plain composable `kurly.http` workload on the
official image: it keeps its config, metadata, and library on a PersistentVolume, so
it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local audiobookshelf = import 'github.com/metio/kurly/workloads/audiobookshelf/server.libsonnet';

kurly.list(audiobookshelf())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `audiobookshelf` | |
| `image` | `ghcr.io/advplyr/audiobookshelf:2.35.1` | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | config, metadata, and library |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:80` — compose an exposure onto it. Put your audiobooks
and podcasts under `/audiobooks` on the volume.

## Persistence

The config and metadata live on a ReadWriteOnce volume, so this is **one replica,
recreated** — the same single-writer discipline as [vaultwarden](../vaultwarden/).

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
metadata: { name: kurly, namespace: audiobookshelf }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-audiobookshelf, namespace: audiobookshelf }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/audiobookshelf, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: audiobookshelf }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-audiobookshelf, namespace: audiobookshelf }
spec: { sourceRef: { kind: OCIRepository, name: kurly-audiobookshelf } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: audiobookshelf, namespace: audiobookshelf }
spec:
  serviceAccountName: audiobookshelf-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/audiobookshelf/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-audiobookshelf, importPath: github.com/metio/kurly/workloads/audiobookshelf }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: audiobookshelf, namespace: audiobookshelf }
spec:
  serviceAccountName: audiobookshelf-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: audiobookshelf
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: audiobookshelf }
```

<!-- END generated: jaas-deploy -->
