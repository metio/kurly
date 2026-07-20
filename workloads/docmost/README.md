<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# docmost

[Docmost](https://github.com/docmost/docmost) — a self-hosted, open-source
collaborative wiki and documentation platform. A plain composable `kurly.http`
workload on the official image, backed by an external PostgreSQL and Redis, with its
attachments on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local docmost = import 'github.com/metio/kurly/workloads/docmost/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='docmost-db', database='docmost')).items,
  kurly.list(docmost(appUrl='https://wiki.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `docmost` | |
| `image` | `docker.io/docmost/docmost:0.95.0` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | attachments (`/app/data/storage`) |
| `appUrl` | inferred | the public URL |
| `secretName` | `docmost-secrets` | Secret with `DATABASE_URL`, `REDIS_URL`, `APP_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:3000` — compose an exposure onto it.

## Backends and secrets

Docmost reads `DATABASE_URL`, `REDIS_URL` and `APP_SECRET` from the environment. kurly
authors **no Secret** — provide `docmost-secrets` holding all three, pulled in via
`envFrom` (fill it with [`kurly.externalSecret`](../../main.libsonnet)). The defaults
pair with a [cnpg-cluster](../cnpg-cluster/) named `docmost-db` and a Redis.

## Persistence

Local attachment storage lives on a ReadWriteOnce volume, so this is **one replica,
recreated**. Point `STORAGE_DRIVER` at S3 to scale past the single writer.
