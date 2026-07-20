<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# metabase

[Metabase](https://github.com/metabase/metabase) — an open-source business-intelligence
and analytics tool. A plain composable `kurly.http` workload on the official image,
backed by an external PostgreSQL for its application database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local metabase = import 'github.com/metio/kurly/workloads/metabase/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='metabase-db', database='metabase')).items,
  kurly.list(metabase()).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `metabase` | |
| `image` | `docker.io/metabase/metabase:v0.62.5` | |
| `dbHost` / `dbName` / `dbUser` | `metabase-db-rw` / `metabase` / `metabase` | the application database |
| `secretName` | `metabase-secrets` | Secret with `MB_DB_PASS` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:3000` — compose an exposure onto it.

## Database and secrets

Metabase reads its application-database coordinates from env and `MB_DB_PASS` from a
provided Secret via `envFrom`. kurly authors **no Secret** — fill `metabase-secrets`
with [`kurly.externalSecret`](../../main.libsonnet). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `metabase-db`. Its state lives in the database,
so it is stateless and can run several replicas.
