<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# miniflux

[Miniflux](https://github.com/miniflux/v2) — a minimalist, opinionated RSS/Atom feed
reader. A plain composable `kurly.http` workload on the official image, backed by an
external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local miniflux = import 'github.com/metio/kurly/workloads/miniflux/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='miniflux-db', database='miniflux')).items,
  kurly.list(miniflux()).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `miniflux` | |
| `image` | `docker.io/miniflux/miniflux:2.3.2` | |
| `secretName` | `miniflux-secrets` | Secret with `DATABASE_URL` and `ADMIN_PASSWORD` (envFrom) |
| `adminUser` | `admin` | the first-run admin username |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:8080` — compose an exposure onto it.

## Database and secrets

Miniflux reads `DATABASE_URL` (with the database password embedded) and the first-run
admin password from the environment. kurly authors **no Secret** — provide
`miniflux-secrets` holding `DATABASE_URL` and `ADMIN_PASSWORD`, pulled in via
`envFrom` (fill it with [`kurly.externalSecret`](../../main.libsonnet)). The defaults
pair with a [cnpg-cluster](../cnpg-cluster/) named `miniflux-db`. Being stateless, it
can run several replicas.
