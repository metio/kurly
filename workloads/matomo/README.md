<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# matomo

[Matomo](https://matomo.org/) — a privacy-focused, self-hosted web-analytics platform,
the open-source Google Analytics alternative. A plain composable `kurly.http` workload
on the official image, backed by an external MySQL/MariaDB, with its config and plugins
on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local matomo = import 'github.com/metio/kurly/workloads/matomo/server.libsonnet';

kurly.list(matomo())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `matomo` | |
| `image` | `docker.io/library/matomo:5.12.0-apache` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | config and plugins (`/var/www/html`) |
| `dbHost` / `dbName` / `dbUser` | `matomo-db` / `matomo` / `matomo` | the MySQL/MariaDB database |
| `secretName` | `matomo-secrets` | Secret with `MATOMO_DATABASE_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and tracking API on `:80` — compose an exposure onto it.

## Database and secrets

Matomo needs a **MySQL/MariaDB** database — the [mysql-cluster](../mysql-cluster/)
workload provides one. It reads its database coordinates from env and
`MATOMO_DATABASE_PASSWORD` from a provided Secret via `envFrom`. kurly authors **no
Secret** — fill `matomo-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. Config and plugins live on a ReadWriteOnce volume, so this is
**one replica, recreated**.
