<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# glitchtip

[GlitchTip](https://glitchtip.com/) — an open-source, Sentry-compatible error-tracking
and performance-monitoring platform. Two composable stages: `server` (the web/ingest
API, `kurly.http`) and `worker` (the Celery worker with beat, `kurly.worker`), on the
official image, backed by an external PostgreSQL and Redis.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local glitchtip = import 'github.com/metio/kurly/workloads/glitchtip/server.libsonnet';
local worker = import 'github.com/metio/kurly/workloads/glitchtip/worker.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='glitchtip-db', database='glitchtip')).items,
  kurly.list(valkey(name='glitchtip-cache')).items,
  kurly.list(glitchtip(domain='https://errors.example.com')).items,
  kurly.list(worker()).items,
]))
```

### `server`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `glitchtip` | |
| `image` | `docker.io/glitchtip/glitchtip:v6.2.2` | |
| `redisHost` | `glitchtip-cache` | the Redis/valkey Service |
| `domain` | inferred | the public URL |
| `secretName` | `glitchtip-secrets` | Secret with `DATABASE_URL` and `SECRET_KEY` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

### `worker`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `glitchtip-worker` | |
| `image` / `redisHost` / `secretName` | as the server | runs `./bin/run-celery-with-beat.sh` |
| `replicas` | `1` | scale out freely — workers coordinate through Redis |
| `env` / `resources` / `labels` / `annotations` | | |

The server serves the web app and the Sentry-compatible ingest API on `:8080` — compose
an exposure onto it.

## Database, cache, and secrets

GlitchTip reads `DATABASE_URL` (with the database password embedded) and `SECRET_KEY`
from a provided Secret via `envFrom`, and `REDIS_URL` and its domain from env. The
defaults pair with a [cnpg-cluster](../cnpg-cluster/) named `glitchtip-db` and a
[valkey](../valkey/) `cache` named `glitchtip-cache`. kurly authors **no Secret** — fill
`glitchtip-secrets` with [`kurly.externalSecret`](../../main.libsonnet).
