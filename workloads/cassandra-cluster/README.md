<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# cassandra-cluster

A highly-available **Apache Cassandra** cluster as a
[cass-operator](https://github.com/k8ssandra/cass-operator) `CassandraDatacenter`
custom resource. Cassandra is **Apache-2.0** (no SSPL/Elastic restriction), a clean
default for a platform that monetizes hosting. This is the wide-column-store
counterpart to [cnpg-cluster](../cnpg-cluster/).

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local cassandra = import 'github.com/metio/kurly/workloads/cassandra-cluster/cluster.libsonnet';

kurly.list(cassandra(name='events', size=3, storageSize='100Gi'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `cassandra` | the datacenter name |
| `clusterName` | = `name` | the Cassandra cluster name |
| `size` | `3` | nodes in this datacenter |
| `serverVersion` | `4.1.7` | the Cassandra version |
| `storageSize` / `storageClass` | `10Gi` / cluster default | per-node data volume |
| `resources` | 1 CPU / 2–4Gi | per-node resources |
| `config` | `{}` | extra `cassandra.yaml` / JVM tuning (cass-operator schema, verbatim) |
| `labels` / `annotations` | | |

Like `cnpg-cluster`, this authors a custom resource, so it is composed **by
parameter, not by `+` feature**.

## Prerequisite

Install **cass-operator** (the DataStax Kubernetes Operator for Apache Cassandra,
Apache-2.0). The operator mints the superuser credentials as a Secret; point apps at
the `<clusterName>-<name>-service` Service.

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
metadata: { name: kurly, namespace: cassandra-cluster }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-cassandra-cluster, namespace: cassandra-cluster }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/cassandra-cluster, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: cassandra-cluster }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-cassandra-cluster, namespace: cassandra-cluster }
spec: { sourceRef: { kind: OCIRepository, name: kurly-cassandra-cluster } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: cassandra-cluster, namespace: cassandra-cluster }
spec:
  serviceAccountName: cassandra-cluster-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local cluster = import 'github.com/metio/kurly/workloads/cassandra-cluster/cluster.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(cluster())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-cassandra-cluster, importPath: github.com/metio/kurly/workloads/cassandra-cluster }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: cassandra-cluster, namespace: cassandra-cluster }
spec:
  serviceAccountName: cassandra-cluster-deployer
  rollbackOnFailure: true
  stages:
    - name: cluster
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: cassandra-cluster
```

<!-- END generated: jaas-deploy -->
