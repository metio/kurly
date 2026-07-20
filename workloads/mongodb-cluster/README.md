<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mongodb-cluster

A highly-available **MongoDB** replica set as a
[MongoDB Community Operator](https://github.com/mongodb/mongodb-kubernetes-operator)
`MongoDBCommunity` custom resource. This is the document-database counterpart to
[cnpg-cluster](../cnpg-cluster/).

## ⚠ Licensing — read this first

MongoDB **Community Edition is licensed under the SSPL**, which restricts *offering
MongoDB as a service* — the same clause that makes Elasticsearch unsuitable for a
monetized hosting platform. The **operator** is Apache-2.0, but the **server** is
not. If SSPL is a problem for your business model, prefer **[FerretDB](https://www.ferretdb.com/)**
(Apache-2.0, MongoDB-wire-compatible, runs on PostgreSQL) instead.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mongodb = import 'github.com/metio/kurly/workloads/mongodb-cluster/cluster.libsonnet';

kurly.list(mongodb(name='sessions', members=3, storageSize='20Gi'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `mongodb` | |
| `members` | `3` | replica-set members (odd count keeps a quorum) |
| `mongodbVersion` | `8.0.4` | the MongoDB server version |
| `storageSize` / `storageClass` | `10Gi` / cluster default | per-member data volume |
| `logsSize` | `2Gi` | per-member logs volume |
| `adminUser` | `admin` | created on bootstrap |
| `secretName` | `mongodb-admin` | **you provide** this Secret (key `password`) |
| `labels` / `annotations` | | |

Like `cnpg-cluster`, this authors a custom resource, so it is composed **by
parameter, not by `+` feature**.

## Prerequisites

1. Install the **MongoDB Community Operator** (`mongodb-kubernetes-operator`).
2. Provide the admin-password **Secret** (`secretName`) with a `password` key. kurly
   authors **no Secret**; fill it with [`kurly.externalSecret`](../../main.libsonnet).

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
metadata: { name: kurly, namespace: mongodb-cluster }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mongodb-cluster, namespace: mongodb-cluster }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mongodb-cluster, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mongodb-cluster }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mongodb-cluster, namespace: mongodb-cluster }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mongodb-cluster } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mongodb-cluster, namespace: mongodb-cluster }
spec:
  serviceAccountName: mongodb-cluster-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local cluster = import 'github.com/metio/kurly/workloads/mongodb-cluster/cluster.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(cluster())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mongodb-cluster, importPath: github.com/metio/kurly/workloads/mongodb-cluster }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mongodb-cluster, namespace: mongodb-cluster }
spec:
  serviceAccountName: mongodb-cluster-deployer
  rollbackOnFailure: true
  stages:
    - name: cluster
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: mongodb-cluster
```

<!-- END generated: jaas-deploy -->
