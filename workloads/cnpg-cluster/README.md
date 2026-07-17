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
| `labels` / `annotations` | `{}` | applied to the Cluster and inherited by every object it generates, pods included |
| `affinity` | — | CNPG's own affinity schema, passed verbatim (see below) |
| `topologySpreadConstraints` | `[]` | passed verbatim |
| `priorityClassName` / `schedulerName` | — | |

## Placement

Databases usually live on their own nodes, behind a taint that keeps everything
else off. That is the cluster's business, so it is passed through rather than
modelled:

```jsonnet
cnpg(
  name='orders-db',
  affinity={
    nodeSelector: { workload: 'database' },
    tolerations: [{ key: 'dedicated', operator: 'Equal', value: 'database', effect: 'NoSchedule' }],
    podAntiAffinityType: 'required',
    topologyKey: 'topology.kubernetes.io/zone',
  },
  priorityClassName='database-critical',
)
```

`affinity` is **CNPG's** schema, not Kubernetes' — it carries `nodeSelector`,
`tolerations`, `podAntiAffinityType`, `topologyKey` and
`additionalPodAffinity`/`additionalPodAntiAffinity` — so consult the
[CNPG API reference](https://cloudnative-pg.io/docs/current/cloudnative-pg.v1/#postgresql-cnpg-io-v1-AffinityConfiguration)
for the fields. kurly passes it verbatim rather than mirroring it, because a
second-hand copy drifts against the operator's and lies about what it accepts.

**`instances: 3` alone does not survive a node loss.** CNPG's anti-affinity is
`preferred` unless told otherwise, so nothing stops all three instances landing
on one node. `podAntiAffinityType: 'required'` makes it a rule — at the price of
instances staying Pending when no node satisfies it.

## Labelling the PostgreSQL pods

The pods belong to the operator, so there is no pod template to attach metadata
to and `kurly.podLabels()` composed onto this workload would land in a config
nothing reads — rendering cleanly and doing nothing. Use the parameters, which
CNPG propagates through `spec.inheritedMetadata`:

```jsonnet
cnpg(
  name='orders-db',
  labels={ team: 'payments' },
  annotations={ 'linkerd.io/inject': 'enabled' },
)
```

Network-policy selectors, sidecar injection and scrape hints reach the
PostgreSQL pods that way.

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

That covers the images in this CR — `imageName`, or whichever the
[catalog](../cnpg-image-catalog/) resolves for the pinned major.

**It is not enough on its own.** CloudNativePG adds its instance manager to every
PostgreSQL pod through an init container running the **operator's own image**, and
that reference comes from the operator's configuration rather than from any
Cluster. Nothing renders it here, so `kurly.mirror` cannot reach it: mirror the
Cluster alone and the pods still fail to pull an init container you never wrote.

The operator's side is operator-wide, set in the `cnpg-controller-manager-config`
ConfigMap (or Secret) in its namespace — see
[Operator configuration](https://cloudnative-pg.io/docs/current/operator_conf/):

| Setting | Covers |
|---|---|
| `OPERATOR_IMAGE_NAME` | the image bootstrapping every PostgreSQL pod |
| `POSTGRES_IMAGE_NAME` | the default for clusters that pin no image |
| `PGBOUNCER_IMAGE_NAME` | Poolers |
| `PULL_SECRET_NAME` | a pull secret the operator copies into every cluster it creates |

The operator's own Deployment is installed from upstream's manifest, so its image
and pull secrets belong to whatever installs it. Between them, `PULL_SECRET_NAME`
and this workload's `imagePullSecrets` overlap: either will do for the clusters
kurly renders, and the operator-wide one also covers clusters it does not.

## Huge pages

PostgreSQL maps `shared_buffers` into **every** backend, and it is a
process-per-connection server. At 4KB pages an 8GB `shared_buffers` is ~2M page
table entries per backend — megabytes of page tables each, multiplied by the
connection count, and a badly thrashed TLB. 2MB huge pages cut that by 512×.

Nothing in CNPG or kurly mediates this: huge pages are an ordinary Kubernetes
resource and PostgreSQL uses them natively, so the existing parameters express it.

```jsonnet
cnpg(
  name='orders-db',
  resources={
    requests: { cpu: '2', memory: '4Gi', 'hugepages-2Mi': '2Gi' },
    limits:   { cpu: '2', memory: '4Gi', 'hugepages-2Mi': '2Gi' },
  },
  parameters={ huge_pages: 'on', shared_buffers: '1800MB' },
)
```

Four things decide whether that works:

- **The node must have them pre-allocated** (`vm.nr_hugepages`, or a boot
  parameter). Kubernetes only schedules against huge pages a node already
  reports; it never allocates them. Without them the pod stays Pending.
- **Request must equal limit.** Huge pages are not overcommittable, and
  Kubernetes rejects the pod otherwise — so the render rejects it first.
- **They do not count toward `memory`.** It is a separate resource, so `memory`
  still has to cover everything that is not `shared_buffers`. Sizing `memory` to
  include the huge pages under-provisions the rest.
- **`huge_pages: 'on'` means PostgreSQL refuses to start without them**, which is
  the reason to set it — the default `'try'` falls back to 4KB silently, so you
  believe you have huge pages and do not. The render therefore fails if `'on'` is
  set with no allocation.

Size the allocation from PostgreSQL rather than from arithmetic: from 15 it
computes the answer itself.

```console
$ postgres -C shared_memory_size_in_huge_pages
1094
```

That is the number of 2MB pages the server actually wants for the configured
`shared_buffers` — shared memory is more than the buffers alone, so a guess of
`shared_buffers` plus a percentage is how allocations end up slightly too small.

Transparent Huge Pages are a different thing and worth disabling: khugepaged's
background compaction is a common source of the latency spikes blamed on running
PostgreSQL in a container. That is a node-level setting — neither CNPG nor kurly
can reach it from a pod spec.

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
