<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# thanos

The [Thanos](https://thanos.io/) components as **separate, independently-scaled
stages** under one workload — they share the Thanos image version but deploy and
scale on their own. Each is a `function(params)` composable app; import the ones
you need and render with `kurly.list`.

| Stage | What it is | Kind |
|---|---|---|
| [`query`](#query) | the Querier — fans out to StoreAPIs for a deduplicated global view | plain `http` Deployment |
| [`query-frontend`](#query-frontend) | optional splitting/caching layer in front of the Querier | plain `http` Deployment |
| [`store`](#store) | serves historical blocks from object storage over the StoreAPI | `stateful` StatefulSet |
| [`compact`](#compact) | compacts, downsamples, and expires blocks in object storage | `http` Deployment (singleton) |
| [`receive`](#receive) | accepts Prometheus remote-write, serves it via the StoreAPI | `stateful` StatefulSet |
| [`ruler`](#ruler) | recording/alerting rules evaluated against the Querier | prometheus-operator `ThanosRuler` CR |

`query` and `query-frontend` are ordinary Deployments — compose `+` features onto
them freely. `ruler` authors a `ThanosRuler` custom resource, so it needs the
**prometheus-operator** installed and rejects composed features (use its
parameters instead), like the [alertmanager](../alertmanager/) and
[prometheus](../prometheus/) workloads.

## query

The stateless Querier: it implements the Prometheus HTTP API by fanning out to
StoreAPI endpoints (Prometheus sidecars, store gateways, rulers, receivers),
deduplicating replicas, and merging into one global view.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local query = import 'github.com/metio/kurly/workloads/thanos/query.libsonnet';

kurly.list(query(endpoints=[
  'dnssrv+_grpc._tcp.prometheus-operated.monitoring.svc.cluster.local',
  'dnssrv+_grpc._tcp.thanos-store-headless.monitoring.svc.cluster.local',
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `thanos-query` | |
| `image` | `quay.io/thanos/thanos:v0.42.2` | |
| `replicas` | `2` | |
| `endpoints` | `[]` | StoreAPI targets (gRPC); `dnssrv+` resolves every replica |
| `queryReplicaLabels` | `['prometheus_replica', 'replica']` | labels to deduplicate across HA replicas |
| `resources` | `100m` / `256Mi` | |
| `labels` / `annotations` / `extraArgs` | `{}` / `[]` | |

Serves the Prometheus-compatible API on the Service at `:10902`; the pod also
serves the StoreAPI over gRPC on `:10901` for a higher-level Querier to federate
(expose it with the raw `+` escape if you nest queriers).

## query-frontend

An **optional** performance layer in front of the Querier: it splits long-range
queries into smaller parallel ones, caches the results (in-memory by default),
and retries transient failures. Run it when queries are large or slow — a plain
Query alone is a complete setup.

```jsonnet
local frontend = import 'github.com/metio/kurly/workloads/thanos/query-frontend.libsonnet';

kurly.list(frontend(downstreamUrl='http://thanos-query.monitoring.svc:10902'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `thanos-query-frontend` | |
| `downstreamUrl` | `http://thanos-query:10902` | the Querier to forward to |
| `replicas` | `2` | |
| `resources` | `100m` / `256Mi` | |
| `image` / `labels` / `annotations` / `extraArgs` | | |

`downstreamUrl` defaults to a `thanos-query` Service in the same namespace — the
`query` stage's own default name — so the two line up out of the box. It serves
the same API on `:10902`, so a Grafana datasource points here instead of at the
Querier. For a cache shared across replicas, pass a
`--query-range.response-cache-config-file` through `extraArgs` and mount it with
`kurly.config`, backed by the [memcached](../memcached/) or [valkey](../valkey/)
workload.

## store

The Store Gateway: it serves historical metric blocks from **object storage**
over the StoreAPI (gRPC), so the Querier reaches data older than the Prometheus
sidecars still hold. Stateful — a per-pod PVC caches block index headers, and its
headless Service gives the Querier `dnssrv+` SRV records.

```jsonnet
local store = import 'github.com/metio/kurly/workloads/thanos/store.libsonnet';

kurly.list(store(objstoreSecret='thanos-objstore'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `thanos-store` | |
| `objstoreSecret` | `thanos-objstore` | Secret (key `objstore.yaml`) naming the bucket — see below |
| `replicas` | `1` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | the local block cache |
| `resources` | `100m` / `512Mi`–`1Gi` | |
| `image` / `labels` / `annotations` / `extraArgs` | | |

Serves the StoreAPI on gRPC `:10901` and metrics/health on HTTP `:10902`. Add it
to the Querier's endpoints via its headless Service:

```jsonnet
query(endpoints=['dnssrv+_grpc._tcp.thanos-store-headless.monitoring.svc.cluster.local'])
```

**Object storage:** the store reads its bucket from a Thanos objstore config — a
YAML naming the bucket, endpoint, and credentials. kurly never mints the Secret
holding it: create one with an `objstore.yaml` key and name it in `objstoreSecret`
(fill it from your secrets store with `kurly.externalSecret`, see the repository
[README](../../#secrets)). It pairs with the [seaweedfs](../seaweedfs/) workload —
point the config at its S3 gateway:

```yaml
# the objstore.yaml key of the Secret
type: S3
config:
  bucket: thanos
  endpoint: seaweedfs-0.seaweedfs-headless.storage.svc:8333
  insecure: true
  access_key: thanos
  secret_key: thanossecret
```

## compact

The Compactor: it compacts raw blocks in object storage into larger ones, builds
the 5m and 1h downsampled resolutions, and applies retention — the background
maintenance that keeps the bucket the [store](#store) reads fast and bounded. It
reads and writes the **same** object store as the store gateway but serves no
StoreAPI.

```jsonnet
local compact = import 'github.com/metio/kurly/workloads/thanos/compact.libsonnet';

kurly.list(compact(objstoreSecret='thanos-objstore', retentionRaw='30d', retention5m='90d', retention1h='1y'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `thanos-compact` | |
| `objstoreSecret` | `thanos-objstore` | the same bucket Secret `store` reads |
| `retentionRaw` / `retention5m` / `retention1h` | `0d` | retention per resolution; `0d` keeps forever |
| `storageSize` / `storageClass` | `10Gi` / cluster default | scratch space for blocks being compacted |
| `resources` / `image` / `labels` / `annotations` / `extraArgs` | | |

**Singleton.** Exactly one compactor may run against a bucket — a second one runs
concurrent compaction over the same blocks and **corrupts the data**. So the
workload pins `replicas` to `1` (composing `+ kurly.replicas(2)` fails the render)
and rolls with `Recreate` so a deploy never briefly overlaps two. Shard a large
bucket by running *separate* compactors, each with a
`--selector.relabel-config` (via `extraArgs`) owning a disjoint slice — never two
over the same slice.

## receive

The Receiver: the **push-based** ingestion path. Point Prometheus `remote_write`
at it (`:19291`) instead of running a Thanos sidecar; it holds recent data in a
local TSDB, serves it to the Querier over the StoreAPI (`:10901`), and uploads
completed blocks to object storage. Receivers form a hashring — series are
distributed across the pods by hash and replicated — so it is a StatefulSet with
a per-pod TSDB PVC.

```jsonnet
local receive = import 'github.com/metio/kurly/workloads/thanos/receive.libsonnet';

kurly.list(receive(replicas=3, replicationFactor=2, objstoreSecret='thanos-objstore'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `thanos-receive` | |
| `replicas` | `1` | each becomes a hashring node |
| `replicationFactor` | `1` | copies of each series across pods (≤ `replicas`) |
| `objstoreSecret` | `thanos-objstore` | the same bucket Secret `store` reads |
| `tsdbRetention` | `15d` | how long the local TSDB keeps data before it lives only in the bucket |
| `storageSize` / `storageClass` | `10Gi` / cluster default | the per-pod TSDB |
| `resources` / `image` / `labels` / `annotations` / `extraArgs` | | |

The **hashring** is generated from the replica count — every pod by its stable
`<name>-<i>.<name>-headless:10901` DNS name — so scaling `replicas` reshapes it.
Prometheus writes to the `remote-write` port (`:19291`); add it to the Querier as
a StoreAPI endpoint via its headless Service:

```jsonnet
query(endpoints=['dnssrv+_grpc._tcp.thanos-receive-headless.monitoring.svc.cluster.local'])
```

Each replica tags its data with a `receive_replica` external label, so the Querier
deduplicates the replicated copies — include it in the Querier's dedup labels:

```jsonnet
query(queryReplicaLabels=['prometheus_replica', 'replica', 'receive_replica'])
```

This runs the combined router+ingestor mode; splitting into dedicated routers is
an `--receive.*` `extraArgs` concern. **Object storage** uses the same
`objstoreSecret` (key `objstore.yaml`) as [store](#store) — kurly never mints it.

## ruler

A Thanos Ruler as a prometheus-operator `ThanosRuler` custom resource: it loads
recording and alerting rules from `PrometheusRule` objects, evaluates them against
Thanos Query (the global view, not one Prometheus), and sends firing alerts to
Alertmanager. **Requires the prometheus-operator installed.**

```jsonnet
local ruler = import 'github.com/metio/kurly/workloads/thanos/ruler.libsonnet';

kurly.list(ruler(
  queryEndpoints=['dnssrv+_http._tcp.thanos-query.monitoring.svc.cluster.local'],
  alertmanagersUrl=['http://alertmanager-operated.monitoring.svc:9093'],
))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `thanos-ruler` | |
| `queryEndpoints` | `[]` | Thanos Query endpoints to evaluate rules against |
| `alertmanagersUrl` | `[]` | plain Alertmanager targets — see below |
| `ruleSelector` / `ruleNamespaceSelector` | `{}` | which `PrometheusRule` objects to load (`{}` = all, absent = none) |
| `storageSize` / `storageClass` | `5Gi` / cluster default | the rule-evaluation WAL/TSDB |
| `replicas` / `image` / `resources` / `labels` / `annotations` / `spec` | | |

The rules it evaluates are ordinary `PrometheusRule` objects — author those
separately. Reach the ruler at `thanos-ruler-operated.<namespace>.svc:10902`.

**Alertmanager auth:** for plain targets, list URLs in `alertmanagersUrl`. For an
authenticated Alertmanager the config lives in a Secret — kurly never mints one,
so reference a Secret you provide through the `spec` escape and fill it with
`kurly.externalSecret` (see the repository [README](../../#secrets)):

```jsonnet
ruler(spec={ alertmanagersConfig: { name: 'thanos-ruler-alertmanager', key: 'config.yaml' } })
```

## Composing the stack

A typical global view: point `query` at your Prometheus sidecars and store
gateways, put `query-frontend` in front of it, and evaluate `ruler` against the
frontend (or the Querier directly).

```jsonnet
kurly.listOf([
  store(objstoreSecret='thanos-objstore'),
  compact(objstoreSecret='thanos-objstore'),
  query(endpoints=[
    'dnssrv+_grpc._tcp.prometheus-operated.monitoring.svc.cluster.local',
    'dnssrv+_grpc._tcp.thanos-store-headless.monitoring.svc.cluster.local',
  ]),
  frontend(downstreamUrl='http://thanos-query:10902'),
  ruler(queryEndpoints=['dnssrv+_http._tcp.thanos-query-frontend.monitoring.svc.cluster.local']),
])
```

Each stage is its own JaaS `JsonnetSnippet` / stageset stage — see the
[alertmanager](../alertmanager/) or [loki](../loki/) README for the full
`OCIRepository` → `JsonnetLibrary` → `StageSet` wiring (substitute
`workloads/thanos` and the stage import path).

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: thanos }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-thanos, namespace: thanos }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/thanos, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: thanos }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-thanos, namespace: thanos }
spec: { sourceRef: { kind: OCIRepository, name: kurly-thanos } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: thanos-compact, namespace: thanos }
spec:
  serviceAccountName: thanos-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local compact = import 'github.com/metio/kurly/workloads/thanos/compact.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(compact())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-thanos, importPath: github.com/metio/kurly/workloads/thanos }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: thanos-query, namespace: thanos }
spec:
  serviceAccountName: thanos-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local query = import 'github.com/metio/kurly/workloads/thanos/query.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(query())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-thanos, importPath: github.com/metio/kurly/workloads/thanos }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: thanos-query-frontend, namespace: thanos }
spec:
  serviceAccountName: thanos-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local query_frontend = import 'github.com/metio/kurly/workloads/thanos/query-frontend.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(query_frontend())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-thanos, importPath: github.com/metio/kurly/workloads/thanos }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: thanos-receive, namespace: thanos }
spec:
  serviceAccountName: thanos-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local receive = import 'github.com/metio/kurly/workloads/thanos/receive.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(receive())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-thanos, importPath: github.com/metio/kurly/workloads/thanos }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: thanos-ruler, namespace: thanos }
spec:
  serviceAccountName: thanos-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local ruler = import 'github.com/metio/kurly/workloads/thanos/ruler.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(ruler())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-thanos, importPath: github.com/metio/kurly/workloads/thanos }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: thanos-store, namespace: thanos }
spec:
  serviceAccountName: thanos-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local store = import 'github.com/metio/kurly/workloads/thanos/store.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(store())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-thanos, importPath: github.com/metio/kurly/workloads/thanos }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: thanos, namespace: thanos }
spec:
  serviceAccountName: thanos-deployer
  rollbackOnFailure: true
  stages:
    - name: compact
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: thanos-compact
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: thanos-compact }
    - name: query
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: thanos-query
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: thanos-query }
    - name: query-frontend
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: thanos-query-frontend
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: thanos-query-frontend }
    - name: receive
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: thanos-receive
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: StatefulSet, name: thanos-receive }
    - name: ruler
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: thanos-ruler
    - name: store
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: thanos-store
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: StatefulSet, name: thanos-store }
```

<!-- END generated: jaas-deploy -->
