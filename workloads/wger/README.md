<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wger

[wger](https://github.com/wger-project/wger) — a self-hosted workout, nutrition,
and body-weight manager. A plain composable `kurly.http` workload on the official
all-in-one image, backed by an external PostgreSQL and Redis, with its uploaded
media on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wger = import 'github.com/metio/kurly/workloads/wger/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='wger-db', database='wger')).items,
  kurly.list(valkey(name='wger-cache')).items,
  kurly.list(wger(siteUrl='https://wger.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wger` | |
| `image` | `docker.io/wger/server:2.6.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | uploaded media (`/home/wger/media`) |
| `dbHost` / `dbName` / `dbUser` | `wger-db-rw` / `wger` / `wger` | the PostgreSQL database |
| `redisHost` | `wger-cache` | the Redis/valkey Service |
| `siteUrl` | inferred | the public URL |
| `secretName` | `wger-secrets` | Secret with `DJANGO_DB_PASSWORD` and `SECRET_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Database, cache, and secrets

wger reads its database and cache coordinates and its `SECRET_KEY` from the
environment. The non-secret coordinates default to a [cnpg-cluster](../cnpg-cluster/)
named `wger-db` and a [valkey](../valkey/) `cache` named `wger-cache`; the sensitive
values (`DJANGO_DB_PASSWORD`, `SECRET_KEY`) come from a provided Secret via
`envFrom`. kurly authors **no Secret** — fill `wger-secrets` with
[`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The all-in-one image runs nginx + uWSGI + Celery and binds `:80`, so this workload
relaxes kurly's non-root and read-only-rootfs defaults while keeping dropped
capabilities and no privilege escalation. Uploaded media lives on a ReadWriteOnce
volume, so this is **one replica, recreated**.
