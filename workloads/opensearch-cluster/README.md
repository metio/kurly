<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# opensearch-cluster

A highly-available **OpenSearch** cluster as an
[OpenSearch Operator](https://github.com/opensearch-project/opensearch-k8s-operator)
`OpenSearchCluster` custom resource, with optional OpenSearch Dashboards.

**Why OpenSearch, not Elasticsearch:** OpenSearch is **Apache-2.0**. Elasticsearch is
SSPL / Elastic License (AGPL since 8.16), all of which restrict *offering the software
as a service* — so OpenSearch is the right default for a platform that monetizes
hosting. This is the search/analytics counterpart to [cnpg-cluster](../cnpg-cluster/).

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local opensearch = import 'github.com/metio/kurly/workloads/opensearch-cluster/cluster.libsonnet';

kurly.list(opensearch(name='logs', replicas=3, storageSize='50Gi'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `opensearch` | |
| `replicas` | `3` | default node-pool size (each node is cluster_manager + data + ingest) |
| `opensearchVersion` | `2.19.1` | server and Dashboards image tag |
| `storageSize` / `storageClass` | `10Gi` / cluster default | per-node data volume |
| `resources` | 500m / 2–4Gi | per-node resources |
| `dashboards` / `dashboardsReplicas` | `true` / `1` | run OpenSearch Dashboards (the Kibana equivalent) |
| `labels` / `annotations` | | |

Like `cnpg-cluster`, this authors a custom resource, so it is composed **by
parameter, not by `+` feature** — composing a kurly feature onto it fails the render.
For large clusters, split into dedicated node pools (cluster_manager / data / ingest)
through the raw `+` escape hatch on `spec.nodePools`.

## Prerequisite

Install the **OpenSearch Operator** (`opensearch-operator`) in the cluster; it
reconciles this CR into the StatefulSets, Services, security config, and Dashboards.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: opensearch-cluster }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-opensearch-cluster, namespace: opensearch-cluster }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/opensearch-cluster, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: opensearch-cluster }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-opensearch-cluster, namespace: opensearch-cluster }
spec: { sourceRef: { kind: OCIRepository, name: kurly-opensearch-cluster } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: opensearch-cluster, namespace: opensearch-cluster }
spec:
  serviceAccountName: opensearch-cluster-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local cluster = import 'github.com/metio/kurly/workloads/opensearch-cluster/cluster.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(cluster())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-opensearch-cluster, importPath: github.com/metio/kurly/workloads/opensearch-cluster }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: opensearch-cluster, namespace: opensearch-cluster }
spec:
  serviceAccountName: opensearch-cluster-deployer
  rollbackOnFailure: true
  stages:
    - name: cluster
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: opensearch-cluster
```

<!-- END generated: jaas-deploy -->
