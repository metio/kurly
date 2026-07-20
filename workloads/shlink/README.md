<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# shlink

[Shlink](https://shlink.io/) — a self-hosted URL shortener with a REST API and rich
analytics. A plain composable `kurly.http` workload on the official image, backed by
an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local shlink = import 'github.com/metio/kurly/workloads/shlink/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='shlink-db', database='shlink')).items,
  kurly.list(shlink(defaultDomain='s.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `shlink` | |
| `image` | `docker.io/shlinkio/shlink:5.1.5` | |
| `dbHost` / `dbName` / `dbUser` | `shlink-db-rw` / `shlink` / `shlink` | the PostgreSQL database |
| `defaultDomain` | required | the short-URL domain |
| `secretName` | `shlink-secrets` | Secret with `DB_PASSWORD` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the short-URL routes and REST API on `:8080` — compose an exposure onto it.

## Database and secrets

Shlink reads its database coordinates from env and `DB_PASSWORD` from a provided Secret
via `envFrom`. kurly authors **no Secret** — fill `shlink-secrets` with
[`kurly.externalSecret`](../../main.libsonnet). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `shlink-db`. Its state lives in the database, so
it is stateless and can run several replicas.
