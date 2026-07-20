<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# directus

[Directus](https://github.com/directus/directus) — an open-source headless CMS and
data platform over your SQL database. A plain composable `kurly.http` workload on the
official image, backed by an external PostgreSQL, with its uploads on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local directus = import 'github.com/metio/kurly/workloads/directus/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='directus-db', database='directus')).items,
  kurly.list(directus(publicUrl='https://cms.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `directus` | |
| `image` | `docker.io/directus/directus:12.1.1` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | uploads (`/directus/uploads`) |
| `dbHost` / `dbName` / `dbUser` | `directus-db-rw` / `directus` / `directus` | the PostgreSQL database |
| `publicUrl` | inferred | the public URL |
| `adminEmail` | `admin@example.com` | the first-run admin |
| `secretName` | `directus-secrets` | Secret with `DB_PASSWORD`, `KEY`, `SECRET`, `ADMIN_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the admin app and API on `:8055` — compose an exposure onto it.

## Database and secrets

Directus reads its database coordinates from env, and `DB_PASSWORD`, `KEY`, `SECRET`,
and the first-run `ADMIN_PASSWORD` from a provided Secret via `envFrom`. kurly authors
**no Secret** — fill `directus-secrets` with
[`kurly.externalSecret`](../../main.libsonnet). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `directus-db`.

## Persistence

Uploaded files live on a ReadWriteOnce volume, so this is **one replica, recreated**.
