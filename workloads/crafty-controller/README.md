<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# crafty-controller

[Crafty Controller](https://gitlab.com/crafty-controller/crafty-4) — a web
control panel that installs, starts, stops and backs up Minecraft servers. A
composable `kurly.http` workload; the panel's own state, the game servers it
manages and their backups each live on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local crafty = import 'github.com/metio/kurly/workloads/crafty-controller/server.libsonnet';

kurly.list(crafty())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `crafty-controller` | |
| `image` | `registry.gitlab.com/crafty-controller/crafty-4:4.9.0` | |
| `configSize` | `1Gi` | `/crafty/app/config` — config, TLS certificate, SQLite database |
| `serversSize` | `20Gi` | `/crafty/servers` — jars, worlds, mods |
| `backupsSize` | `20Gi` | `/crafty/backups` |
| `storageClass` | cluster default | shared by all three claims |
| `env` / `resources` / `labels` / `annotations` | | |

## It speaks HTTPS, and only HTTPS

The panel listens on `:8443` with a certificate it generates for itself, and
there is no plaintext listener at all. An exposure composed onto this workload
therefore has to talk TLS to the backend — the Ingress annotation your controller
uses for an HTTPS upstream, or a `BackendTLSPolicy` beside the HTTPRoute. Probes
are by connection for the same reason: there is no path to fetch without
presenting a certificate nobody has a reason to trust.

## The game servers run inside this pod

Crafty launches each Minecraft server as its own JVM under the panel process.
The pod's CPU and memory limits are the budget for **every server it hosts**, not
just for the panel, so the defaults here — sized for the panel alone — are a
starting point and nothing else. Raise them per server you intend to run.

Which ports those servers listen on is decided in the panel at runtime, so this
workload publishes none of them. Add them once you know:

```jsonnet
crafty() + kurly.extraPort('mc-survival', 25565)
```

## Persistence

Three ReadWriteOnce volumes, so this is **one replica, recreated** (never
rolled). The panel keeps its accounts and its server inventory in a SQLite
database under `/crafty/app/config`; a second pod writing to it while the first
still holds it is not something SQLite recovers from.

## Hardened, with two relaxations

The launcher takes the non-root path it documents for Kubernetes — it execs the
panel directly rather than `sudo`-ing to its own account — so the pod runs as the
image's unprivileged user with every capability dropped. Two things give:

- **the root group**, because every file in the image is `crafty:root` with group
  write, which is also how the volumes arrive writable (`fsGroup: 0`)
- **a writable root filesystem**, because the panel refuses to start unless its
  working directory is writable and keeps logs and migration markers inside the
  image's own tree

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
metadata: { name: kurly, namespace: crafty-controller }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-crafty-controller, namespace: crafty-controller }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/crafty-controller, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: crafty-controller }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-crafty-controller, namespace: crafty-controller }
spec: { sourceRef: { kind: OCIRepository, name: kurly-crafty-controller } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: crafty-controller, namespace: crafty-controller }
spec:
  serviceAccountName: crafty-controller-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/crafty-controller/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-crafty-controller, importPath: github.com/metio/kurly/workloads/crafty-controller }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: crafty-controller, namespace: crafty-controller }
spec:
  serviceAccountName: crafty-controller-deployer
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
        name: crafty-controller
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: crafty-controller }
```

<!-- END generated: jaas-deploy -->
