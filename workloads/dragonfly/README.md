<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# dragonfly

A [Dragonfly](https://www.dragonflydb.io/) server — a RESP-speaking in-memory
store — as a `kurly.stateful` workload with a per-pod PVC and a headless Service.
Clients reach it at `<pod>.dragonfly-headless.<namespace>.svc` on port 6379.

Dragonfly answers the same protocol as [valkey](../valkey/), so a client cannot
tell them apart. It is **not a fork** of Valkey or Redis, though, and the
differences land in exactly the places a workload has to get right.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local dragonfly = import 'github.com/metio/kurly/workloads/dragonfly/instance.libsonnet';

kurly.list(dragonfly(maxMemoryMB=2048, threads=4, storageSize='10Gi'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `dragonfly` | also names the Service — see below |
| `image` | `ghcr.io/dragonflydb/dragonfly:v1.39.0` | published on GHCR, not Docker Hub |
| `storageSize` | `1Gi` | the per-pod volume, mounted at `/data` |
| `storageClass` | cluster default | |
| `maxMemoryMB` | `512` | the dataset cap; also derives the container memory limit |
| `threads` | `2` | `--proactor_threads`, and the CPU request |
| `snapshotCron` | — | crontab expression for periodic snapshots |

## Why the threads and the memory are tied together

Dragonfly runs **one io thread per core it can see**, and in a container that is
the node's core count — not the pod's CPU limit. It then refuses to start unless
`maxmemory` is at least **256MiB per io thread**:

```text
Running 16 io threads
There are 16 threads, so 4.00GiB are required. Exiting...
```

Those two compound. Left to itself on a 64-core node, Dragonfly starts 64
threads, demands 16GiB, and exits before serving anything — however small the
pod's CPU limit is. So this workload always pins `--proactor_threads`, sizes the
CPU request from it (a thread per core is Dragonfly's model), and checks the
memory floor **at render**:

```text
dragonfly: maxMemoryMB must be at least 1024 (256MiB per io thread × 4 threads),
or Dragonfly refuses to start
```

Better a failed render than a CrashLoop whose reason is buried in a log.

## Persistence

Dragonfly has no `--appendonly` — the flag is unknown to it, and an unknown flag
is fatal. It snapshots instead: on shutdown by default, and on a schedule when
`snapshotCron` is set. For a cache that need not survive a crash, leave it unset.

## Either store, one consumer

The protocol is the same, so name the workload for its **role** and a consumer
never learns which store answered:

```jsonnet
kurly.list(dragonfly(name='cache'))          // or valkey's instance(), likewise
worker + kurly.env({ REDIS_URL: 'redis://cache-headless:6379' })
```

The consumer takes an endpoint, not a workload — swapping Dragonfly for Valkey
is then a change to one manifest and nothing else.

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
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: dragonfly }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-dragonfly, namespace: dragonfly }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/dragonfly, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: dragonfly }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-dragonfly, namespace: dragonfly }
spec: { sourceRef: { kind: OCIRepository, name: kurly-dragonfly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: dragonfly, namespace: dragonfly }
spec:
  serviceAccountName: dragonfly-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local instance = import 'github.com/metio/kurly/workloads/dragonfly/instance.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(instance())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-dragonfly, importPath: github.com/metio/kurly/workloads/dragonfly }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: dragonfly, namespace: dragonfly }
spec:
  serviceAccountName: dragonfly-deployer
  rollbackOnFailure: true
  stages:
    - name: instance
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: dragonfly
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: StatefulSet, name: dragonfly }
```

<!-- END generated: jaas-deploy -->
