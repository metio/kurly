<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# peertube

[PeerTube](https://joinpeertube.org/) — a decentralized, federated video platform.
A plain composable `kurly.http` workload on the official image, backed by an
external PostgreSQL and Redis, with its videos, uploads, and config on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local peertube = import 'github.com/metio/kurly/workloads/peertube/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='peertube-db', database='peertube')).items,
  kurly.list(valkey(name='peertube-cache')).items,
  kurly.list(peertube(webserverHost='videos.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `peertube` | |
| `image` | `docker.io/chocobozzz/peertube:v8.2.2-trixie` | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | videos, uploads, config |
| `dbHost` / `dbName` / `dbUser` | `peertube-db-rw` / `peertube` / `peertube` | the PostgreSQL database |
| `redisHost` | `peertube-cache` | the Redis/valkey Service |
| `webserverHost` | required | the public hostname (federation depends on it) |
| `secretName` | `peertube-secrets` | Secret with `PEERTUBE_DB_PASSWORD`, `PEERTUBE_SECRET`, `PT_INITIAL_ROOT_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:9000` — compose an exposure onto it.

## Database, cache, and secrets

PeerTube reads its database and Redis coordinates and its secrets from the
environment. The non-secret coordinates default to a [cnpg-cluster](../cnpg-cluster/)
named `peertube-db` and a [valkey](../valkey/) `cache` named `peertube-cache`; the
sensitive values come from a provided Secret via `envFrom`. kurly authors **no
Secret** — fill `peertube-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

## Persistence

Videos and uploads live on a ReadWriteOnce volume, so this is **one replica,
recreated**. Large instances move storage to S3-compatible object storage (the
[seaweedfs](../seaweedfs/) workload) — beyond this recipe's default.
