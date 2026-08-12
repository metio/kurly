<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# dgraph

[Dgraph](https://dgraph.io) — a distributed graph database queried with GraphQL
and DQL. Two composable `kurly.stateful` stages: `zero`, the coordinator, and
`alpha`, which holds the graph.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local zero = import 'github.com/metio/kurly/workloads/dgraph/zero.libsonnet';
local alpha = import 'github.com/metio/kurly/workloads/dgraph/alpha.libsonnet';

kurly.list([
  zero(replicas=3, shardReplicas=3),
  alpha(replicas=3, whitelist=['10.0.0.0/8']),
])
```

| Parameter (zero) | Default | Notes |
|---|---|---|
| `replicas` | `1` | this stage's Raft membership — odd numbers |
| `shardReplicas` | `1` | how many alphas hold each copy of the graph |
| `storageSize` / `storageClass` | `10Gi` / cluster default | the write-ahead log |

| Parameter (alpha) | Default | Notes |
|---|---|---|
| `replicas` | `1` | shards, not copies |
| `zeroHost` / `zeroPort` | `dgraph-zero-headless` / `5080` | |
| `whitelist` | `[]` | CIDRs allowed to call the admin API |
| `storageSize` / `storageClass` | `50Gi` / cluster default | posting list and WAL |

Alpha serves HTTP and GraphQL on `:8080` and gRPC on `:9080`. Zero serves gRPC on
`:5080` and its admin HTTP on `:6080` — neither belongs on the internet, since
`:6080` will move data and drop nodes for anyone who asks.

## The two halves need each other

Zero holds no graph data; it decides who holds what. An alpha that cannot reach a
zero waits rather than serving. Deploy both, zero first.

## One zero is not high availability

Raft needs an odd number to tolerate a loss, so a cluster that must survive one
failure wants three replicas. One is the default because it is what a single-node
deployment needs, and because three costs three volumes.

## Replicas are shards, not copies

Raising alpha's `replicas` adds capacity. How many copies exist of each piece of
data is zero's `shardReplicas`. Setting one without the other is how a Dgraph
deployment ends up with no redundancy while looking three times bigger.

## Security is off until you turn it on

Dgraph's admin endpoints accept whoever reaches them. `whitelist` is the CIDR list
allowed to call the admin API, and it defaults to nothing rather than to the
private ranges — a default that admits a whole cluster network is not one anybody
chose. ACLs and encryption at rest are Enterprise features; the open-source build
has the whitelist and whatever sits in front of it.

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
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: dgraph }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-dgraph, namespace: dgraph }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/dgraph, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: dgraph }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-dgraph, namespace: dgraph }
spec: { sourceRef: { kind: OCIRepository, name: kurly-dgraph } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: dgraph-alpha, namespace: dgraph }
spec:
  serviceAccountName: dgraph-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local alpha = import 'github.com/metio/kurly/workloads/dgraph/alpha.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(alpha())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-dgraph, importPath: github.com/metio/kurly/workloads/dgraph }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: dgraph-zero, namespace: dgraph }
spec:
  serviceAccountName: dgraph-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local zero = import 'github.com/metio/kurly/workloads/dgraph/zero.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(zero())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-dgraph, importPath: github.com/metio/kurly/workloads/dgraph }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: dgraph, namespace: dgraph }
spec:
  serviceAccountName: dgraph-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: alpha
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: dgraph-alpha
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: StatefulSet, name: dgraph-alpha }
    - name: zero
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: dgraph-zero
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: StatefulSet, name: dgraph-zero }
```

<!-- END generated: jaas-deploy -->
