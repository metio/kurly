<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# bookstack

[BookStack](https://www.bookstackapp.com/) — a simple, self-hosted platform for
organising and storing documentation. A plain composable `kurly.http` workload on the
maintained [LinuxServer](https://docs.linuxserver.io/images/docker-bookstack/) image,
backed by an external MySQL/MariaDB, with its config and uploads on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local bookstack = import 'github.com/metio/kurly/workloads/bookstack/server.libsonnet';

kurly.list(bookstack(appUrl='https://docs.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `bookstack` | |
| `image` | `lscr.io/linuxserver/bookstack:26.05.2` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | config and uploads (`/config`) |
| `dbHost` / `dbName` / `dbUser` | `bookstack-db` / `bookstack` / `bookstack` | the MySQL/MariaDB database |
| `appUrl` | inferred | the public URL |
| `secretName` | `bookstack-secrets` | Secret with `DB_PASS` and `APP_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Database and secrets

BookStack needs a **MySQL/MariaDB** database — the [mysql-cluster](../mysql-cluster/)
workload provides one. It reads its database coordinates from env and `DB_PASS` and
`APP_KEY` from a provided Secret via `envFrom`. kurly authors **no Secret** — fill
`bookstack-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The LinuxServer image runs its s6 init as **root** and binds `:80`, so this workload
relaxes kurly's non-root and read-only-rootfs defaults while keeping dropped
capabilities and no privilege escalation. Config and uploads live on a ReadWriteOnce
volume, so this is **one replica, recreated**.
