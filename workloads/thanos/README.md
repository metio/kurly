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
