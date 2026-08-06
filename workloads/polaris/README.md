<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# polaris

[Polaris](https://github.com/agersant/polaris) — a music streaming server for your
own collection, with a web client and a documented HTTP API. A plain composable
`kurly.http` workload: the database, the cache and the music library all live on one
PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local polaris = import 'github.com/metio/kurly/workloads/polaris/server.libsonnet';

kurly.list(polaris())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `polaris` | |
| `image` | `quay.io/connectical/polaris:0.16.1-alpine3.24.1` | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | database (`/var/lib/polaris`), cache and music share the volume |
| `env` | `{}` | extra `POLARIS_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web client and the API on `:5050` — compose an exposure onto it. Put your
music under `/music` on the volume, then add that directory in Polaris' settings so
it is indexed. The first account you create through the web client is the admin.

## Entrypoint

The image's `run-polaris` wrapper passes the data directory as `-d`, which this
version of Polaris no longer accepts, and its own defaults are derived from `HOME`,
which the image does not set. The binary is therefore called directly with every
path stated. The wrapper also reads `POLARIS_PORT` as the port to listen on, which a
Service named after the workload would inject as a `tcp://` URL — service links are
disabled as well.

## Persistence

The database lives on a ReadWriteOnce volume, so this is **one replica, recreated** —
the same single-writer discipline as [navidrome](../navidrome/).

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
metadata: { name: kurly, namespace: polaris }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-polaris, namespace: polaris }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/polaris, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: polaris }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-polaris, namespace: polaris }
spec: { sourceRef: { kind: OCIRepository, name: kurly-polaris } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: polaris, namespace: polaris }
spec:
  serviceAccountName: polaris-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/polaris/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-polaris, importPath: github.com/metio/kurly/workloads/polaris }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: polaris, namespace: polaris }
spec:
  serviceAccountName: polaris-deployer
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
        name: polaris
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: polaris }
```

<!-- END generated: jaas-deploy -->
