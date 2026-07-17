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

## Deploy through JaaS and stageset

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-dragonfly, namespace: cache }
spec:
  interval: 12h
  url: oci://ghcr.io/metio/kurly/workloads/dragonfly
  ref: { tag: latest }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-dragonfly, namespace: cache }
spec: { sourceRef: { kind: OCIRepository, name: kurly-dragonfly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: cache, namespace: cache }
spec:
  serviceAccountName: cache-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local dragonfly = import 'github.com/metio/kurly/workloads/dragonfly/instance.libsonnet';
      function(maxMemoryMB='2048', threads='4')
        kurly.list(dragonfly(
          name='cache',
          maxMemoryMB=std.parseInt(maxMemoryMB),
          threads=std.parseInt(threads),
        ))
  libraries:
    - { kind: JsonnetLibrary, name: kurly,           importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-dragonfly, importPath: github.com/metio/kurly/workloads/dragonfly }
  tlas:
    - name: maxMemoryMB
      value: "2048"
    - name: threads
      value: "4"
---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: cache, namespace: cache }
spec:
  serviceAccountName: cache-deployer
  stages:
    - name: cache
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: cache
      readyChecks:
        checks:
          - apiVersion: apps/v1
            kind: StatefulSet
            name: cache
```
