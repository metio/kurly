<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# etherpad

[Etherpad](https://etherpad.org/) — a real-time collaborative document editor. A
plain composable `kurly.http` workload on the official image, backed by an external
PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local etherpad = import 'github.com/metio/kurly/workloads/etherpad/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='etherpad-db', database='etherpad')).items,
  kurly.list(etherpad()).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `etherpad` | |
| `image` | `docker.io/etherpad/etherpad:3.3.2` | |
| `dbHost` / `dbName` / `dbUser` | `etherpad-db-rw` / `etherpad` / `etherpad` | the PostgreSQL database |
| `secretName` | `etherpad-secrets` | Secret with `DB_PASS`, `ADMIN_PASSWORD`, `APIKEY` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the editor and API on `:9001` — compose an exposure onto it.

## Database and secrets

Etherpad reads its database coordinates and `DB_PASS`, plus `ADMIN_PASSWORD` and
`APIKEY`, from the environment. The non-secret coordinates default to a
[cnpg-cluster](../cnpg-cluster/) named `etherpad-db`; the secrets come from a provided
Secret via `envFrom`. kurly authors **no Secret** — fill `etherpad-secrets` with
[`kurly.externalSecret`](../../main.libsonnet). Its documents live in the database, so
it is stateless and can run several replicas.
