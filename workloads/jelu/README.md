<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# jelu

[Jelu](https://github.com/bayang/jelu) — a book tracker for the books you have
read, are reading and want to read. A plain composable `kurly.http` workload on
the official image: the embedded SQLite database, the Lucene search index and the
uploaded files all live on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local jelu = import 'github.com/metio/kurly/workloads/jelu/server.libsonnet';

kurly.list(jelu())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `jelu` | |
| `image` | `docker.io/wabayang/jelu:0.84.6` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | database, search index, uploaded files |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:11111` — compose an exposure onto it.

## Storage and configuration

The database and log live at `/database`, the cover images and import files at
`/files`, both on the one volume. The Lucene search index defaults to the working
directory — where the application's own jar sits, on a read-only root filesystem —
so it is pointed at `/database/lucene` through the environment; binding
`jelu.lucene` that way replaces the whole object, which is why the index analyzer's
defaults are restated alongside it. A Spring configuration directory can be mounted
at `/config`.

Service links are off: a Service named after this workload makes Kubernetes inject
`JELU_PORT` as a `tcp://` URL, which Spring's relaxed binding reads as
configuration.

## Persistence

The database lives on a ReadWriteOnce volume, so this is **one replica,
recreated** — the same single-writer discipline as
[audiobookshelf](../audiobookshelf/).

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

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
metadata: { name: kurly, namespace: jelu }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-jelu, namespace: jelu }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/jelu, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: jelu }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-jelu, namespace: jelu }
spec: { sourceRef: { kind: OCIRepository, name: kurly-jelu } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: jelu, namespace: jelu }
spec:
  serviceAccountName: jelu-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/jelu/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-jelu, importPath: github.com/metio/kurly/workloads/jelu }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: jelu, namespace: jelu }
spec:
  serviceAccountName: jelu-deployer
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
        name: jelu
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: jelu }
```

<!-- END generated: jaas-deploy -->
