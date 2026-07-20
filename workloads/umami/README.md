<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# umami

[Umami](https://github.com/umami-software/umami) — a simple, privacy-focused,
self-hosted web-analytics alternative to Google Analytics. A plain composable
`kurly.http` workload on the official image, backed by an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local umami = import 'github.com/metio/kurly/workloads/umami/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='umami-db', database='umami')).items,
  kurly.list(umami()).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `umami` | |
| `image` | `ghcr.io/umami-software/umami:postgresql-v2.15.1` | the PostgreSQL image variant |
| `secretName` | `umami-secrets` | Secret with `DATABASE_URL` and `APP_SECRET` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the dashboard and tracking API on `:3000` — compose an exposure onto it.

## Database and secrets

Umami reads `DATABASE_URL` (with the database password embedded) and `APP_SECRET`
from the environment. kurly authors **no Secret** — provide `umami-secrets` holding
both, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `umami-db`. Being stateless, it can run several
replicas.
