<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# twenty

[Twenty](https://github.com/twentyhq/twenty) — a modern, open-source CRM. Two
composable stages: `server` (the web/API front end, `kurly.http`) and `worker` (the
background BullMQ worker, `kurly.worker`), on the official image, backed by an
external PostgreSQL and Redis.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local twenty = import 'github.com/metio/kurly/workloads/twenty/server.libsonnet';
local worker = import 'github.com/metio/kurly/workloads/twenty/worker.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='twenty-db', database='twenty')).items,
  kurly.list(valkey(name='twenty-cache')).items,
  kurly.list(twenty(serverUrl='https://crm.example.com')).items,
  kurly.list(worker()).items,
]))
```

### `server`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `twenty` | |
| `image` | `docker.io/twentycrm/twenty:v2.22.0` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | local uploads |
| `redisHost` | `twenty-cache` | the Redis/valkey Service |
| `serverUrl` | inferred | the public URL |
| `secretName` | `twenty-secrets` | Secret with `PG_DATABASE_URL` and `APP_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

### `worker`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `twenty-worker` | |
| `image` / `redisHost` / `secretName` | as the server | runs `yarn worker:prod` |
| `replicas` | `1` | scale out freely — workers coordinate through Redis |
| `env` / `resources` / `labels` / `annotations` | | |

The server serves the app and API on `:3000` — compose an exposure onto it.

## Database, cache, and secrets

Twenty reads `REDIS_URL` and its server URL from env, and `PG_DATABASE_URL` (with
the database password embedded) and `APP_SECRET` from a provided Secret via
`envFrom`. The defaults pair with a [cnpg-cluster](../cnpg-cluster/) named
`twenty-db` and a [valkey](../valkey/) `cache` named `twenty-cache`. kurly authors
**no Secret** — fill `twenty-secrets` with
[`kurly.externalSecret`](../../main.libsonnet).

## Persistence

With local file storage the server keeps uploads on a ReadWriteOnce volume, so it is
**one replica, recreated**. Move `STORAGE_TYPE` to S3 (the [seaweedfs](../seaweedfs/)
workload) to scale the front end horizontally; the worker holds no state and scales
with `replicas`.
