<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# listmonk

[listmonk](https://github.com/knadh/listmonk) — a self-hosted newsletter and
mailing-list manager. A plain composable `kurly.http` workload on the official image,
backed by an external PostgreSQL, with its uploaded media on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local listmonk = import 'github.com/metio/kurly/workloads/listmonk/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='listmonk-db', database='listmonk')).items,
  kurly.list(listmonk()).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `listmonk` | |
| `image` | `docker.io/listmonk/listmonk:v6.2.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | uploaded media (`/listmonk/uploads`) |
| `dbHost` / `dbName` / `dbUser` | `listmonk-db-rw` / `listmonk` / `listmonk` | the PostgreSQL database |
| `adminUser` | `admin` | the admin username |
| `secretName` | `listmonk-secrets` | Secret with `LISTMONK_db__password` and `LISTMONK_app__admin_password` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the admin UI and API on `:9000` — compose an exposure onto it.

## Database and secrets

listmonk reads its database and admin coordinates from the environment. The non-secret
coordinates default to a [cnpg-cluster](../cnpg-cluster/) named `listmonk-db`; the
passwords come from a provided Secret via `envFrom`. kurly authors **no Secret** — fill
`listmonk-secrets` with [`kurly.externalSecret`](../../main.libsonnet). Run the
one-time schema install (`./listmonk --install`) against the database before first use.

## Persistence

Uploaded media lives on a ReadWriteOnce volume, so this is **one replica, recreated**.
