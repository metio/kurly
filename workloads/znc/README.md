<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# znc

[ZNC](https://znc.in/) — an IRC bouncer that stays connected to IRC and replays
what you missed. A plain composable `kurly.http` workload on the official image
that keeps its configuration, module data, and buffers on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local znc = import 'github.com/metio/kurly/workloads/znc/server.libsonnet';

kurly.list(znc())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `znc` | |
| `image` | `docker.io/library/znc:1.10.2` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the data volume (`/znc-data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves IRC and the web admin on `:6697` — route it as TCP through a LoadBalancer or
a Gateway TCPRoute.

## Configuration

ZNC needs a `znc.conf` (with user credentials) at `/znc-data/configs/znc.conf`
**before it starts**. Generate one with `znc --makeconf` and place it on the volume,
or mount it from a Secret (kurly mints none — it holds passwords).

## Persistence

The configuration and buffers live on a ReadWriteOnce volume, so this is **one
replica, recreated** (never rolled) to keep two pods off the files.

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
metadata: { name: kurly, namespace: znc }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-znc, namespace: znc }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/znc, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: znc }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-znc, namespace: znc }
spec: { sourceRef: { kind: OCIRepository, name: kurly-znc } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: znc, namespace: znc }
spec:
  serviceAccountName: znc-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/znc/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-znc, importPath: github.com/metio/kurly/workloads/znc }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: znc, namespace: znc }
spec:
  serviceAccountName: znc-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: znc
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: znc }
```

<!-- END generated: jaas-deploy -->
