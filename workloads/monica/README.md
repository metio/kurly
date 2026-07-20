<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# monica

[Monica](https://www.monicahq.com/) — a self-hosted personal relationship manager:
keep track of your interactions with the people who matter. A plain composable
`kurly.http` workload on the official image, backed by an external MySQL/MariaDB, with
its uploads on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local monica = import 'github.com/metio/kurly/workloads/monica/server.libsonnet';

kurly.list(monica(appUrl='https://monica.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `monica` | |
| `image` | `docker.io/library/monica:4.1.2-apache` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | uploads (`/var/www/html/storage`) |
| `dbHost` / `dbName` / `dbUser` | `monica-db` / `monica` / `monica` | the MySQL/MariaDB database |
| `appUrl` | inferred | the public URL |
| `secretName` | `monica-secrets` | Secret with `DB_PASSWORD` and `APP_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Database and secrets

Monica needs a **MySQL/MariaDB** database — the [mysql-cluster](../mysql-cluster/)
workload provides one. It reads its database coordinates from env and `DB_PASSWORD` and
`APP_KEY` from a provided Secret via `envFrom`. kurly authors **no Secret** — fill
`monica-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. Uploads live on a ReadWriteOnce volume, so this is **one
replica, recreated**.
