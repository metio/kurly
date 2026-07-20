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
