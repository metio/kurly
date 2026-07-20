<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# bugsink

[Bugsink](https://www.bugsink.com/) — a self-hosted, Sentry-compatible error tracker:
it ingests the same events your existing Sentry SDKs already emit. A plain composable
`kurly.http` workload on the official image, backed by an external PostgreSQL or MySQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local bugsink = import 'github.com/metio/kurly/workloads/bugsink/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='bugsink-db', database='bugsink')).items,
  kurly.list(bugsink(baseUrl='https://errors.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `bugsink` | |
| `image` | `docker.io/bugsink/bugsink:2.4.0` | |
| `replicas` | `2` | stateless — scale freely |
| `baseUrl` | inferred | the public URL (validated Host header) |
| `behindHttps` | `true` | secure-cookie / HTTPS handling |
| `secretName` | `bugsink-secrets` | Secret with `DATABASE_URL` and `SECRET_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and the event-ingestion API on `:8000` — compose an exposure onto it.

## Database and secrets

Bugsink reads `DATABASE_URL` and `SECRET_KEY` from the environment. kurly authors **no
Secret** — provide `bugsink-secrets` holding both, pulled in via `envFrom` (fill it
with [`kurly.externalSecret`](../../main.libsonnet)). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `bugsink-db`.

## Persistence

Backed by an external database, events live in the DB, so this is **stateless** — a
plain rolling Deployment with no volume.
