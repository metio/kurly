<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# druid

[Apache Druid](https://github.com/apache/druid) — a column-oriented analytics
store for interactive queries over event data: it ingests streams and files,
keeps them as immutable time-partitioned segments in deep storage, and answers
aggregations over billions of rows in about as long as it takes to ask.

Druid is not one process. It is five services with different jobs, and this
workload carries one stage each.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local coordinator = import 'github.com/metio/kurly/workloads/druid/coordinator.libsonnet';
local historical = import 'github.com/metio/kurly/workloads/druid/historical.libsonnet';
local middleManager = import 'github.com/metio/kurly/workloads/druid/middle-manager.libsonnet';
local broker = import 'github.com/metio/kurly/workloads/druid/broker.libsonnet';
local router = import 'github.com/metio/kurly/workloads/druid/router.libsonnet';

kurly.list([
  coordinator(),
  historical(),
  middleManager(),
  broker(),
  router(),
])
```

| Stage | Port | What it does |
|---|---|---|
| `coordinator` | 8081 | assigns segments to the historicals and, running as Overlord, accepts ingestion tasks |
| `historical` | 8083 | holds segments in a local cache and answers queries over them |
| `middle-manager` | 8091 | runs ingestion tasks in forked peon processes |
| `broker` | 8082 | takes the query, fans it out, merges the answer |
| `router` | 8888 | the console and one proxied front door |

**Deploy them in that order.** The coordinator creates the metadata tables the
others read, and a broker that starts against an empty schema has nothing to
plan against. A `StageSet` gates each stage on the one before it, which is what
that ordering is for.

## No ZooKeeper

A classic Druid deployment coordinates through a ZooKeeper ensemble. These
stages do not: every one of them loads `druid-kubernetes-extensions` and runs
with HTTP-based segment and task management, so the services announce
themselves by labelling their own pods, discover each other by watching those
labels, and elect leaders through a ConfigMap lease. The Kubernetes API server
is already highly available and already there; a second consensus system to keep
running is not.

Two consequences travel with that choice:

- Each stage declares a Role over `pods` and `configmaps` in its own namespace,
  via `kurly.apiServerClient` — so the ServiceAccount, the Role, the binding and
  the egress allowance come with the workload and merge with, rather than
  replace, a consumer's own `rbac()` and `networkPolicy()`.
- **All stages of one Druid cluster must share a namespace and a
  `clusterIdentifier`.** Two Druid deployments in one namespace need two
  identifiers, or each will discover the other's services and try to use them.

A pod's own hostname does not resolve, so each stage advertises its routable pod
IP as `druid.host` through the downward API. That is the address the other
services actually dial.

## What it needs from outside

**A PostgreSQL** for metadata — datasources, the segment table, task and
supervisor state. Every stage must point at the same one. The
[cnpg-cluster](../cnpg-cluster/) workload provides one.

**An S3-compatible bucket** for deep storage: the segments themselves and the
task logs. This is not optional and it is not a volume. Deep storage is written
by the middle-manager and read by the historicals at the same time, which a
ReadWriteOnce volume cannot serve — and a segment that only exists on one node's
disk is a segment that disappears when that node does. Point `s3Endpoint` at a
MinIO, [SeaweedFS](../seaweedfs/) or Ceph gateway, or leave it unset for AWS S3
itself. Path-style addressing is on, which is what those gateways serve.

**A Secret** holding `druid_metadata_storage_connector_password`,
`druid_s3_accessKey` and `druid_s3_secretKey`. kurly authors none. Those key
names are environment variable names: the image translates every `druid_*`
variable into the Druid property of the same name with `_` replaced by `.`,
which is how a credential reaches Druid without a configuration file being
written anywhere.

## Sizing, because the image is sized for a machine

The configuration baked into the image is the one Druid publishes for dedicated
servers: half-gigabyte processing buffers, fifteen processing threads on a
historical, a 300 GiB segment cache, four concurrent tasks at a gigabyte of heap
each. None of that fits a modest container, and a stage that inherited it would
be killed before it finished starting.

So each stage sets its own `heap`, `directMemory` and processing buffers, and
the defaults here are deliberately small — enough to run a real Druid, not
enough to make it fast. Raise them together with `resources`, and mind the one
arithmetic rule Druid enforces: a broker or historical needs
`(numMergeBuffers + numThreads + 1)` processing buffers to fit inside
`directMemory`, or it refuses to start.

The middle-manager has a second rule of its own: **the peons run inside its
pod**, each as its own JVM. `workerCapacity × peonHeap` is memory that container
needs on top of its own heap, which is why its limit sits so far above it.

## Storage

Only the historical claims a volume, and that volume is a **cache**. The record
is in deep storage; a historical that loses its segment cache downloads the
segments again and is merely slow for a while. It is still a ReadWriteOnce
volume with one writer, so that stage is one replica, recreated (never rolled)
to keep two historicals off the same cache directory. `segmentCacheSize` is a
hard budget Druid refuses to load past, and it belongs below `storageSize` — a
cache allowed to grow to the size of its volume leaves the JVM's own scratch
nowhere to go.

Everything else writes only working directories, so the coordinator, broker,
router and middle-manager run on emptyDirs and scale horizontally.

## Exposing it

The router is the stage an exposure goes onto. Nothing else should be reachable
from outside.

**Druid ships no authentication** until the `druid-basic-security` extension is
configured. The console the router serves can drop datasources, submit ingestion
tasks and read every row in every table, and it will do all of that for whoever
reaches it. An exposure on its own publishes an administrative interface. Keep
it inside the cluster and query it from your own application, or put something
in front that authenticates.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
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
metadata: { name: kurly, namespace: druid }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-druid, namespace: druid }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/druid, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: druid }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-druid, namespace: druid }
spec: { sourceRef: { kind: OCIRepository, name: kurly-druid } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: druid-broker, namespace: druid }
spec:
  serviceAccountName: druid-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local broker = import 'github.com/metio/kurly/workloads/druid/broker.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(broker())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-druid, importPath: github.com/metio/kurly/workloads/druid }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: druid-coordinator, namespace: druid }
spec:
  serviceAccountName: druid-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local coordinator = import 'github.com/metio/kurly/workloads/druid/coordinator.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(coordinator())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-druid, importPath: github.com/metio/kurly/workloads/druid }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: druid-historical, namespace: druid }
spec:
  serviceAccountName: druid-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local historical = import 'github.com/metio/kurly/workloads/druid/historical.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(historical())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-druid, importPath: github.com/metio/kurly/workloads/druid }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: druid-middle-manager, namespace: druid }
spec:
  serviceAccountName: druid-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local middle_manager = import 'github.com/metio/kurly/workloads/druid/middle-manager.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(middle_manager())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-druid, importPath: github.com/metio/kurly/workloads/druid }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: druid-router, namespace: druid }
spec:
  serviceAccountName: druid-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local router = import 'github.com/metio/kurly/workloads/druid/router.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(router())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-druid, importPath: github.com/metio/kurly/workloads/druid }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: druid, namespace: druid }
spec:
  serviceAccountName: druid-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: broker
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: druid-broker
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: druid-broker }
    - name: coordinator
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: druid-coordinator
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: druid-coordinator }
    - name: historical
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: druid-historical
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: druid-historical }
    - name: middle-manager
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: druid-middle-manager
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: druid-middle-manager }
    - name: router
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: druid-router
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: druid-router }
```

<!-- END generated: jaas-deploy -->
