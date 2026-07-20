<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wikijs

[Wiki.js](https://github.com/requarks/wiki) — a modern, open-source wiki. A plain
composable `kurly.http` workload on the official image, backed by an external
PostgreSQL. Its content and configuration live in the database, so the workload is
stateless and can run several replicas.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wikijs = import 'github.com/metio/kurly/workloads/wikijs/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='wikijs-db', database='wikijs')).items,
  kurly.list(wikijs()).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wikijs` | |
| `image` | `ghcr.io/requarks/wiki:2.5.314` | |
| `dbHost` / `dbName` / `dbUser` | `wikijs-db-rw` / `wikijs` / `wikijs` | the PostgreSQL database |
| `secretName` | `wikijs-secrets` | Secret with `DB_PASS` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the wiki and API on `:3000` — compose an exposure onto it.

## Database and secrets

Wiki.js reads its database coordinates from env and `DB_PASS` from a provided Secret
via `envFrom`. kurly authors **no Secret** — fill `wikijs-secrets` with
[`kurly.externalSecret`](../../main.libsonnet). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `wikijs-db`. Its content lives in the database,
so it is stateless and can run several replicas.
