<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mautic

[Mautic](https://github.com/mautic/mautic) — open-source marketing automation. A
plain composable `kurly.http` workload on the official Apache image, backed by an
external MySQL/MariaDB, with its configuration and uploaded media on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mautic = import 'github.com/metio/kurly/workloads/mautic/server.libsonnet';

kurly.list(mautic(siteUrl='https://mautic.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `mautic` | |
| `image` | `docker.io/mautic/mautic:5.2.11-apache` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | config + media |
| `dbHost` / `dbName` / `dbUser` | `mautic-db` / `mautic` / `mautic` | the MySQL/MariaDB database |
| `siteUrl` | inferred | the public URL |
| `secretName` | `mautic-secrets` | Secret with `MAUTIC_DB_PASSWORD` (envFrom) |
| `runCronJobs` | `true` | run Mautic's background jobs in-container |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Database and secrets

Mautic needs a **MySQL/MariaDB** database. kurly ships no MySQL recipe — bring your
own and point `dbHost` at it. It reads `MAUTIC_DB_HOST`, `MAUTIC_DB_NAME`,
`MAUTIC_DB_USER` from env and `MAUTIC_DB_PASSWORD` from a provided Secret via
`envFrom`. kurly authors **no Secret** — fill `mautic-secrets` with
[`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities
and no privilege escalation. Configuration and media live on a ReadWriteOnce
volume, so this is **one replica, recreated**.
