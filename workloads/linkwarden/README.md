<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# linkwarden

[Linkwarden](https://github.com/linkwarden/linkwarden) — a self-hosted bookmark
manager that archives a copy of every page. A plain composable `kurly.http` workload
on the official image, backed by an external PostgreSQL, with its archived pages on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local linkwarden = import 'github.com/metio/kurly/workloads/linkwarden/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='linkwarden-db', database='linkwarden')).items,
  kurly.list(linkwarden(nextauthUrl='https://links.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `linkwarden` | |
| `image` | `ghcr.io/linkwarden/linkwarden:v2.15.1` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | archived pages (`/data/data`) |
| `nextauthUrl` | inferred | the public URL |
| `secretName` | `linkwarden-secrets` | Secret with `DATABASE_URL` and `NEXTAUTH_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:3000` — compose an exposure onto it.

## Database and secrets

Linkwarden reads `DATABASE_URL` (with the database password embedded) and
`NEXTAUTH_SECRET` from the environment. kurly authors **no Secret** — provide
`linkwarden-secrets` holding both, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `linkwarden-db`.

## Persistence

With local storage, archived pages live on a ReadWriteOnce volume, so this is **one
replica, recreated**. Move storage to S3 (the [seaweedfs](../seaweedfs/) workload) to
scale out.
