<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# snipe-it

[Snipe-IT](https://github.com/snipe/snipe-it) — a free, open-source IT asset and
license management system. A plain composable `kurly.http` workload on the official
image, backed by an external MySQL/MariaDB, with its uploads on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local snipeit = import 'github.com/metio/kurly/workloads/snipe-it/server.libsonnet';

kurly.list(snipeit(appUrl='https://assets.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `snipe-it` | |
| `image` | `docker.io/snipe/snipe-it:v8.6.3` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | uploads (`/var/lib/snipeit`) |
| `dbHost` / `dbName` / `dbUser` | `snipe-it-db` / `snipeit` / `snipeit` | the MySQL/MariaDB database |
| `appUrl` | inferred | the public URL |
| `secretName` | `snipe-it-secrets` | Secret with `DB_PASSWORD` and `APP_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:80` — compose an exposure onto it.

## Database and secrets

Snipe-IT needs a **MySQL/MariaDB** database — the [mysql-cluster](../mysql-cluster/)
workload provides one. It reads its database coordinates from env and `DB_PASSWORD` and
`APP_KEY` from a provided Secret via `envFrom`. kurly authors **no Secret** — fill
`snipe-it-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. Uploads live on a ReadWriteOnce volume, so this is **one
replica, recreated**.
