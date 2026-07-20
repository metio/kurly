<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# activepieces

[Activepieces](https://www.activepieces.com) — a self-hosted, open-source no-code
automation / workflow builder, à la Zapier. A plain composable `kurly.http` workload on
the official all-in-one image, backed by an external PostgreSQL and Redis.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local activepieces = import 'github.com/metio/kurly/workloads/activepieces/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='activepieces-db', database='activepieces')).items,
  kurly.list(activepieces(frontendUrl='https://flows.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `activepieces` | |
| `image` | `docker.io/activepieces/activepieces:0.86.3` | |
| `replicas` | `2` | stateless — scale freely |
| `frontendUrl` | inferred | the public URL (webhook URLs derive from it) |
| `secretName` | `activepieces-secrets` | `AP_POSTGRES_*`, `AP_REDIS_*`, `AP_ENCRYPTION_KEY`, `AP_JWT_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves on `:80` — compose an exposure onto it.

## Persistence

Flow state lives in PostgreSQL and Redis, so this is **stateless** — a plain rolling
Deployment.
