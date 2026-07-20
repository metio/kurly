<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# prometheus

A [Prometheus](https://prometheus.io/) server as a
[prometheus-operator](https://github.com/prometheus-operator/prometheus-operator)
`Prometheus` custom resource, with the cluster-scoped RBAC it scrapes with. Like
[cnpg-cluster](../cnpg-cluster/), this authors the CR directly — the operator
reconciles it into a StatefulSet, the pods, and the `prometheus-operated`
Service.

**Prerequisite:** the prometheus-operator (its CRDs and controller) must be
installed in the cluster.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local prometheus = import 'github.com/metio/kurly/workloads/prometheus/server.libsonnet';

kurly.list(prometheus(namespace='monitoring', retention='30d', storageSize='100Gi'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `prometheus` | |
| `namespace` | `monitoring` | **must match where you deploy** — see below |
| `image` | `docker.io/prom/prometheus:v3.13.1` | |
| `replicas` | `1` | |
| `retention` | `15d` | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | the data volume |
| `scrapeInterval` | `30s` | |
| `resources` | `500m` / `2Gi` | request/limit |
| `externalLabels` | `{}` | labels stamped on every sample (e.g. `cluster`) |
| `serviceMonitorSelector` etc. | `{}` | what to scrape — see below |
| `namespaceSelector` | `{}` | which namespaces to scrape from |
| `spec` | `{}` | extra `Prometheus` spec fields, merged verbatim |

## Why `namespace` matters

The workload creates a `ClusterRole` and `ClusterRoleBinding` so Prometheus can
read the whole cluster to discover targets. A `ClusterRoleBinding` is
cluster-scoped, so it names the `ServiceAccount` by namespace **in the object
itself** — nothing can fill that in later. So `namespace` must be the namespace
you actually deploy to; the workload also stamps it on the `ServiceAccount` and
the `Prometheus` CR to keep the three consistent.

## What it scrapes

Prometheus discovers targets from `ServiceMonitor`, `PodMonitor`, `Probe`, and
`PrometheusRule` objects. The selectors decide which it honours, and
`namespaceSelector` decides which namespaces they may live in. The defaults are
**central monitoring** — every selector is `{}`, which matches everything, in
every namespace — so a fresh Prometheus scrapes the whole cluster. Narrow it by
passing a label selector:

```jsonnet
prometheus(
  namespace='monitoring',
  serviceMonitorSelector={ matchLabels: { 'monitoring.example.com/scrape': 'true' } },
  namespaceSelector={ matchLabels: { 'monitoring.example.com/scrape': 'true' } },
)
```

The selectors are the operator's own schema, passed verbatim; likewise `spec`
merges any other `Prometheus` field (`thanos`, `remoteWrite`,
`additionalScrapeConfigs`, `enableRemoteWriteReceiver`, …) that this workload
does not surface as a parameter.

## Query it

The operator creates a headless Service for every Prometheus in the namespace, so
reach the API and UI at:

```text
http://prometheus-operated.<namespace>.svc:9090
```

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
metadata: { name: kurly, namespace: prometheus }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-prometheus, namespace: prometheus }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/prometheus, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: prometheus }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-prometheus, namespace: prometheus }
spec: { sourceRef: { kind: OCIRepository, name: kurly-prometheus } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: prometheus, namespace: prometheus }
spec:
  serviceAccountName: prometheus-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/prometheus/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-prometheus, importPath: github.com/metio/kurly/workloads/prometheus }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: prometheus, namespace: prometheus }
spec:
  serviceAccountName: prometheus-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: prometheus
```

<!-- END generated: jaas-deploy -->
