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
