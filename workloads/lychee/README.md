<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# lychee

[Lychee](https://github.com/LycheeOrg/Lychee) — a self-hosted photo-management and
gallery system. A plain composable `kurly.http` workload on the official image: with
the SQLite backend its config, database, and photos live on a PersistentVolume, so it
needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local lychee = import 'github.com/metio/kurly/workloads/lychee/server.libsonnet';

kurly.list(lychee(appUrl='https://photos.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `lychee` | |
| `image` | `docker.io/lycheeorg/lychee:v7.7.1` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | photos (`/uploads`), config (`/conf`), symlinks (`/sym`) |
| `appUrl` | inferred | the public URL |
| `secretName` | `lychee-secrets` | Secret with `APP_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the gallery and API on `:80` — compose an exposure onto it.

## Security and persistence

The nginx + PHP-FPM image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. Config, database, and photos live on a ReadWriteOnce volume,
so this is **one replica, recreated**. Point `DB_CONNECTION` at external MySQL/PostgreSQL
to scale past the single SQLite writer.
