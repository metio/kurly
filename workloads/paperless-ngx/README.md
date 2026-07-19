<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# paperless-ngx

[Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) — scan, index, and
archive your documents with OCR and full-text search. A plain composable
`kurly.http` workload backed by an external PostgreSQL and Redis, with its data,
media, consume, and export trees on a PersistentVolume. The image runs the web
server and its Celery workers together, so one deployment is the whole app.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local paperless = import 'github.com/metio/kurly/workloads/paperless-ngx/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='paperless-db', database='paperless')).items,
  kurly.list(valkey(name='paperless-cache')).items,
  kurly.list(paperless(url='https://paperless.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `paperless-ngx` | |
| `image` | `ghcr.io/paperless-ngx/paperless-ngx:2.20.15` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | the document archive (data/media/consume/export) |
| `dbHost` / `dbName` / `dbUser` | `paperless-db-rw` / `paperless` / `paperless` | the PostgreSQL database |
| `redisHost` | `paperless-cache` | the Redis/valkey Service |
| `url` | inferred | the public URL |
| `adminUser` | `admin` | the first-run admin username |
| `secretName` | `paperless-ngx-secrets` | Secret with `PAPERLESS_DBPASS`, `PAPERLESS_SECRET_KEY`, `PAPERLESS_ADMIN_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:8000` — compose an exposure onto it.

## Database, cache, and secrets

Paperless reads its database and Redis coordinates and its secrets from the
environment. The non-secret coordinates default to a [cnpg-cluster](../cnpg-cluster/)
named `paperless-db` and a [valkey](../valkey/) `cache` named `paperless-cache`; the
sensitive values come from a provided Secret via `envFrom`. kurly authors **no
Secret** — fill `paperless-ngx-secrets` with
[`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The entrypoint and Celery workers write to the root filesystem, so this workload
relaxes kurly's read-only-rootfs default while keeping non-root, dropped
capabilities, and no privilege escalation. The document archive lives on a
ReadWriteOnce volume (four trees under one volume), so this is **one replica,
recreated**.
