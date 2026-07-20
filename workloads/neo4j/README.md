<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# neo4j

[Neo4j](https://neo4j.com/) — the graph database, on the official Community image.
Unlike the other database workloads (which author operator CRs), Neo4j Community has
**no Kubernetes operator and does not cluster** — clustering is an Enterprise feature
— so this is a plain composable `kurly.http` **single-instance** workload; its graph
lives on a PersistentVolume.

Community Edition is **GPLv3** (fine to run; GPL obligations attach to distribution,
not operation). Clustering / HA needs Neo4j Enterprise, beyond this recipe.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local neo4j = import 'github.com/metio/kurly/workloads/neo4j/server.libsonnet';

kurly.list(neo4j())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `neo4j` | |
| `image` | `docker.io/library/neo4j:5.26.28-community` | 5.26 LTS |
| `storageSize` / `storageClass` | `10Gi` / cluster default | the graph store (`/data`) |
| `secretName` | `neo4j-secrets` | Secret with `NEO4J_AUTH` (`neo4j/<password>`, envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the HTTP/Browser API on `:7474` and Bolt on `:7687` — compose an exposure onto
the HTTP port and route Bolt as TCP.

## Auth and persistence

Neo4j reads `NEO4J_AUTH` from the environment. kurly authors **no Secret** — provide
`neo4j-secrets` holding it, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The graph lives on a ReadWriteOnce
volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: neo4j }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-neo4j, namespace: neo4j }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/neo4j, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: neo4j }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-neo4j, namespace: neo4j }
spec: { sourceRef: { kind: OCIRepository, name: kurly-neo4j } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: neo4j, namespace: neo4j }
spec:
  serviceAccountName: neo4j-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/neo4j/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-neo4j, importPath: github.com/metio/kurly/workloads/neo4j }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: neo4j, namespace: neo4j }
spec:
  serviceAccountName: neo4j-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: neo4j
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: neo4j }
```

<!-- END generated: jaas-deploy -->
