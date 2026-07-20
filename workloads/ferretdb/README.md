<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ferretdb

[FerretDB](https://www.ferretdb.com/) — an open-source, MongoDB-compatible database.
It is a **stateless** proxy that speaks the MongoDB wire protocol and stores
everything in a PostgreSQL backend (with the DocumentDB extension), so this workload
needs no volume of its own and can run several replicas.

**Why FerretDB:** it is **Apache-2.0** and MongoDB-wire-compatible — the permissive
alternative to MongoDB Community (SSPL) for a platform that monetizes hosting. See
[mongodb-cluster](../mongodb-cluster/) for the SSPL engine.

## Compose

FerretDB v2 needs a PostgreSQL with the **DocumentDB extension**. Run one with
[cnpg-cluster](../cnpg-cluster/) pinned to the FerretDB image, then point FerretDB at
it:

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ferretdb = import 'github.com/metio/kurly/workloads/ferretdb/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='ferretdb-db', imageName='ghcr.io/ferretdb/postgres-documentdb:17')).items,
  kurly.list(ferretdb()).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `ferretdb` | |
| `image` | `ghcr.io/ferretdb/ferretdb:2.7.0` | the proxy image |
| `secretName` | `ferretdb-secrets` | Secret with `FERRETDB_POSTGRESQL_URL` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the MongoDB wire protocol on `:27017` — route it as TCP for MongoDB clients.

## Backend and secrets

kurly authors **no Secret** — provide `ferretdb-secrets` holding
`FERRETDB_POSTGRESQL_URL` (with the backend password), pulled in via `envFrom` (fill
it with [`kurly.externalSecret`](../../main.libsonnet)). The backend is a PostgreSQL
with the DocumentDB extension; the `ghcr.io/ferretdb/postgres-documentdb` image
provides it, run through `cnpg-cluster`.
