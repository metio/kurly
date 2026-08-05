<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# tubesync

[TubeSync](https://github.com/meeb/tubesync) — subscribe to YouTube channels and
playlists and it downloads new uploads on a schedule, named and tagged so Plex or
Jellyfin picks them up as an ordinary library. A plain composable `kurly.http`
workload with two PersistentVolumes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local tubesync = import 'github.com/metio/kurly/workloads/tubesync/server.libsonnet';

kurly.list(tubesync())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `tubesync` | |
| `image` | `ghcr.io/meeb/tubesync:v0.18.3` | |
| `storageSize` | `5Gi` | database and configuration (`/config`) |
| `mediaSize` | `200Gi` | downloaded media (`/downloads`) |
| `puid` / `pgid` | `1000` | ownership the media is written with |
| `env` / `resources` / `labels` / `annotations` | | |

## Two volumes, and why `puid` matters

The database is small and roughly fixed; the media directory grows without limit.
They are separate parameters so the expensive one can be sized — and put on a
different storage class — independently.

`puid`/`pgid` decide the ownership downloaded files get. If a media server shares
that volume, these have to be an identity it can read, which is the usual reason
to change them.

## Less hardened, deliberately

This is an s6-overlay image: the init runs as root, prepares both directories for
its own account and drops to it, with no path through as an unprivileged process.
So root, the capabilities the drop needs, the escalation that permits it, and a
writable root filesystem are all required — the same shape as the other
LinuxServer-style workloads in this catalogue.

## Persistence

One database on a ReadWriteOnce volume, so this is **one replica, recreated**
(never rolled). That is not only about the file: two schedulers would fetch the
same videos twice.

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
metadata: { name: kurly, namespace: tubesync }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-tubesync, namespace: tubesync }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/tubesync, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: tubesync }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-tubesync, namespace: tubesync }
spec: { sourceRef: { kind: OCIRepository, name: kurly-tubesync } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: tubesync, namespace: tubesync }
spec:
  serviceAccountName: tubesync-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/tubesync/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-tubesync, importPath: github.com/metio/kurly/workloads/tubesync }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: tubesync, namespace: tubesync }
spec:
  serviceAccountName: tubesync-deployer
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
        name: tubesync
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: tubesync }
```

<!-- END generated: jaas-deploy -->
