<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# navidrome

[Navidrome](https://github.com/navidrome/navidrome) — a modern music server and
streamer, compatible with Subsonic/Airsonic clients. A plain composable `kurly.http`
workload on the official image: it keeps its database on a PersistentVolume and reads
your music library from it, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local navidrome = import 'github.com/metio/kurly/workloads/navidrome/server.libsonnet';

kurly.list(navidrome())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `navidrome` | |
| `image` | `docker.io/deluan/navidrome:0.63.2` | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | database (`/data`) and music (`/music`) |
| `env` | `{}` | extra `ND_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and Subsonic API on `:4533` — compose an exposure onto it. Put your
music under `/music` on the volume.

## Persistence

The database lives on a ReadWriteOnce volume, so this is **one replica, recreated** —
the same single-writer discipline as [vaultwarden](../vaultwarden/).

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
metadata: { name: kurly, namespace: navidrome }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-navidrome, namespace: navidrome }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/navidrome, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: navidrome }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-navidrome, namespace: navidrome }
spec: { sourceRef: { kind: OCIRepository, name: kurly-navidrome } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: navidrome, namespace: navidrome }
spec:
  serviceAccountName: navidrome-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/navidrome/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-navidrome, importPath: github.com/metio/kurly/workloads/navidrome }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: navidrome, namespace: navidrome }
spec:
  serviceAccountName: navidrome-deployer
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
        name: navidrome
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: navidrome }
```

<!-- END generated: jaas-deploy -->
