<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ghost

[Ghost](https://ghost.org/) — a modern, open-source publishing and newsletter
platform. A plain composable `kurly.http` workload on the official image, backed by an
external MySQL/MariaDB, with its content (themes, images, uploads) on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ghost = import 'github.com/metio/kurly/workloads/ghost/server.libsonnet';

kurly.list(ghost(url='https://blog.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `ghost` | |
| `image` | `docker.io/library/ghost:5.130.6-alpine` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | content (`/var/lib/ghost/content`) |
| `dbHost` / `dbName` / `dbUser` | `ghost-db` / `ghost` / `ghost` | the MySQL/MariaDB database |
| `url` | inferred | the public URL |
| `secretName` | `ghost-secrets` | Secret with the DB password (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the site and admin on `:2368` — compose an exposure onto it.

## Database and secrets

Ghost needs a **MySQL/MariaDB** database — the [mysql-cluster](../mysql-cluster/)
workload provides one. It reads its database coordinates from env and the database
password from a provided Secret via `envFrom`. kurly authors **no Secret** — fill
`ghost-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

## Persistence

The content lives on a ReadWriteOnce volume, so this is **one replica, recreated**.
