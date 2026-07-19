<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# maybe

[Maybe](https://github.com/maybe-finance/maybe) — a self-hosted personal finance
and net-worth manager. A plain composable `kurly.http` workload backed by an
external PostgreSQL and Redis, with its Active Storage uploads on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local maybe = import 'github.com/metio/kurly/workloads/maybe/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='maybe-db', database='maybe')).items,
  kurly.list(valkey(name='maybe-cache')).items,
  kurly.list(maybe()).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `maybe` | |
| `image` | `ghcr.io/maybe-finance/maybe:0.1.0-alpha.6` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | Active Storage uploads (`/rails/storage`) |
| `dbHost` / `dbName` / `dbUser` | `maybe-db-rw` / `maybe` / `maybe` | the PostgreSQL database |
| `redisHost` | `maybe-cache` | the Redis/valkey Service |
| `secretName` | `maybe-secrets` | Secret with `POSTGRES_PASSWORD` and `SECRET_KEY_BASE` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:3000` — compose an exposure onto it.

## Database, cache, and secrets

Maybe reads its database and Redis coordinates and its `SECRET_KEY_BASE` from the
environment. The non-secret coordinates default to a [cnpg-cluster](../cnpg-cluster/)
named `maybe-db` and a [valkey](../valkey/) `cache` named `maybe-cache`; the
sensitive values come from a provided Secret via `envFrom`. kurly authors **no
Secret** — fill `maybe-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The Rails app writes to several paths under `/rails` at runtime, so this workload
relaxes kurly's read-only-rootfs default while keeping non-root, dropped
capabilities, and no privilege escalation. Active Storage uploads live on a
ReadWriteOnce volume, so this is **one replica, recreated**. A separate Sidekiq
worker (background jobs) can be added as a second deployment.
