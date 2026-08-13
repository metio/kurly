<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# komga

[Komga](https://github.com/gotson/komga) — a media server for comics, manga, and
digital books. A plain composable `kurly.http` workload on the official image: it
keeps its database and thumbnails and reads its library from a PersistentVolume, so
it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local komga = import 'github.com/metio/kurly/workloads/komga/server.libsonnet';

kurly.list(komga())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `komga` | |
| `image` | `docker.io/gotson/komga:1.26.1` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | database (`/config`) and library (`/books`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web UI, OPDS, and API on `:25600` — compose an exposure onto it. Put your
comic/book library under `/books` on the volume.

## Security and persistence

The Java app writes temp files to the root filesystem, so this workload relaxes
kurly's read-only-rootfs default while keeping non-root, dropped capabilities, and no
privilege escalation. The database lives on a ReadWriteOnce volume, so this is **one
replica, recreated**.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage. Delivered end to end through Flux, JaaS and stageset-controller on 2026-07-31, and observed rolling out.

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
metadata: { name: kurly, namespace: komga }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-komga, namespace: komga }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/komga, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: komga }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-komga, namespace: komga }
spec: { sourceRef: { kind: OCIRepository, name: kurly-komga } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: komga, namespace: komga }
spec:
  serviceAccountName: komga-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/komga/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-komga, importPath: github.com/metio/kurly/workloads/komga }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: komga, namespace: komga }
spec:
  serviceAccountName: komga-deployer
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
        name: komga
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: komga }
```

<!-- END generated: jaas-deploy -->
