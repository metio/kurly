<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# hedgedoc

[HedgeDoc](https://github.com/hedgedoc/hedgedoc) — real-time, collaborative markdown
notes. A plain composable `kurly.http` workload on the official image, backed by an
external PostgreSQL, with its uploaded files on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local hedgedoc = import 'github.com/metio/kurly/workloads/hedgedoc/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='hedgedoc-db', database='hedgedoc')).items,
  kurly.list(hedgedoc(domain='pad.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `hedgedoc` | |
| `image` | `quay.io/hedgedoc/hedgedoc:1.11.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | uploaded files |
| `domain` | inferred | the public domain |
| `secretName` | `hedgedoc-secrets` | Secret with `CMD_DB_URL` and `CMD_SESSION_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:3000` — compose an exposure onto it.

## Database and secrets

HedgeDoc reads `CMD_DB_URL` (with the database password embedded) and
`CMD_SESSION_SECRET` from the environment. kurly authors **no Secret** — provide
`hedgedoc-secrets` holding both, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `hedgedoc-db`.

## Persistence

Uploaded files live on a ReadWriteOnce volume, so this is **one replica, recreated**.
