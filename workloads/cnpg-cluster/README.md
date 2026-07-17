<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# cnpg-cluster

A highly-available PostgreSQL cluster, authored as a
[CloudNativePG](https://cloudnative-pg.io/) `Cluster` custom resource. PostgreSQL
is always run through CNPG here — this workload writes the CR with sensible
defaults (three instances, a bootstrapped application database, a PodMonitor),
and the CNPG operator reconciles it into the StatefulSet, pods, Services, and
failover machinery.

**Prerequisite:** the CloudNativePG operator must be installed in the cluster.

## Compose

The stage is a `function(params)` returning the CR; adapt it and render with
`kurly.list`:

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list(cnpg(
  name='orders-db',
  instances=3,
  storageSize='20Gi',
  storageClass='fast-ssd',
  database='orders',
  owner='orders',
  parameters={ max_connections: '200' },
))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `postgres` | Cluster (and CR) name |
| `instances` | `3` | one primary + N-1 hot-standby replicas |
| `storageSize` | `10Gi` | per-instance volume size |
| `storageClass` | operator default | |
| `imageName` | operator default | pin a PostgreSQL image to control the major version |
| `database` / `owner` | `app` / `app` | the bootstrapped application database and its role |
| `parameters` | `{}` | extra `postgresql.conf` parameters |
| `resources` | — | container requests/limits |
| `enablePodMonitor` | `true` | a PodMonitor for the Prometheus Operator |
| `imagePullSecrets` | `[]` | names of existing Secrets the operator pulls PostgreSQL with |

## Pulling from a private registry

The operator pulls PostgreSQL itself, so the pull secrets belong to the Cluster —
`kurly.imagePullSecrets()` is a pod-level feature and there is no pod here to
attach it to. Point the images at the registry with
[`kurly.mirror`](../../#private-registries) and name the secrets on the cluster:

```jsonnet
kurly.mirror('harbor.internal/dockerhub', kurly.list(
  cnpg(name='orders-db', catalog='postgres', major=17, imagePullSecrets=['regcred'])
))
```

## Deploy through JaaS and stageset

```yaml
# The kurly library and this workload's source, from their release pipelines.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: postgres }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-cnpg-cluster, namespace: postgres }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/cnpg-cluster, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: postgres }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-cnpg-cluster, namespace: postgres }
spec: { sourceRef: { kind: OCIRepository, name: kurly-cnpg-cluster } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: postgres, namespace: postgres }
spec:
  serviceAccountName: postgres-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
      function(instances='3', storageSize='20Gi')
        kurly.list(cnpg(name='orders-db', instances=std.parseInt(instances), storageSize=storageSize))
  libraries:
    - { kind: JsonnetLibrary, name: kurly,               importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-cnpg-cluster,  importPath: github.com/metio/kurly/workloads/cnpg-cluster }
  tlas:
    - name: instances
      value: "3"
    - name: storageSize
      value: "20Gi"
---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: postgres, namespace: postgres }
spec:
  serviceAccountName: postgres-deployer
  rollbackOnFailure: true
  stages:
    - name: cluster
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: postgres
      readyChecks:
        checks:
          - apiVersion: postgresql.cnpg.io/v1
            kind: Cluster
            name: orders-db
```
