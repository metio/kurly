<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# restreamer

[Restreamer](https://github.com/datarhei/restreamer) — a complete streaming server
with a web UI. Take a camera or an RTMP feed in, transcode it with FFmpeg, and
publish it as HLS to a website or push it on to YouTube, Twitch and the rest. A
plain composable `kurly.http` workload with two PersistentVolumes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local restreamer = import 'github.com/metio/kurly/workloads/restreamer/server.libsonnet';

kurly.list(restreamer())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `restreamer` | |
| `image` | `datarhei/restreamer:2.9.0` | |
| `configSize` | `1Gi` | `/core/config` |
| `dataSize` | `20Gi` | recordings (`/core/data`) |
| `secretName` | `restreamer` | the admin credentials |
| `resources` | 500m–2 CPU | see below |

## Ports

| port | protocol | for |
|---|---|---|
| 8080 | HTTP | the web UI and HLS — what an exposure attaches to |
| 1935 | TCP | RTMP ingest |
| 1936 | TCP | RTMPS ingest |
| 6000 | UDP | SRT ingest |

Only :8080 is HTTP. Give the ingest ports a `TCPRoute`/`UDPRoute` or a
`LoadBalancer` if publishers are outside the cluster.

## Set the admin credentials before exposing it

`CORE_API_AUTH_USERNAME` and `CORE_API_AUTH_PASSWORD` come from the Secret. Without
them, the first visitor to the web UI is invited to create the administrator
account — which on an instance reachable from the internet means whoever finds it
first.

## The CPU limit is doing a job

Transcoding is CPU work and FFmpeg will use everything it is given. The default
limit of 2 cores is what stops one busy stream starving everything else on the
node. Raise it deliberately for the number of concurrent transcodes you expect —
but removing it is how a single stream takes down its neighbours.

## Persistence

Configuration and recordings are separate volumes so the recording side can be
sized, and placed on a different storage class, without dragging configuration
along. Both are ReadWriteOnce, so this is **one replica, recreated** (never
rolled).

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
metadata: { name: kurly, namespace: restreamer }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-restreamer, namespace: restreamer }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/restreamer, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: restreamer }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-restreamer, namespace: restreamer }
spec: { sourceRef: { kind: OCIRepository, name: kurly-restreamer } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: restreamer, namespace: restreamer }
spec:
  serviceAccountName: restreamer-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/restreamer/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-restreamer, importPath: github.com/metio/kurly/workloads/restreamer }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: restreamer, namespace: restreamer }
spec:
  serviceAccountName: restreamer-deployer
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
        name: restreamer
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: restreamer }
```

<!-- END generated: jaas-deploy -->
