<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# shiori

[Shiori](https://github.com/go-shiori/shiori) — a simple, self-hosted bookmarks
manager with web-page archiving. A plain composable `kurly.http` workload that keeps
its bookmarks and archived pages in SQLite on a PersistentVolume, so it needs no
external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local shiori = import 'github.com/metio/kurly/workloads/shiori/server.libsonnet';

kurly.list(shiori())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `shiori` | |
| `image` | `ghcr.io/go-shiori/shiori:v1.8.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | database and archives (`/shiori`) |
| `env` | `{}` | extra `SHIORI_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:8080` — compose an exposure onto it. Point
`SHIORI_DATABASE_URL` at an external PostgreSQL/MySQL through `env` to scale past the
single SQLite writer.

## Persistence

The SQLite database and archives live on a ReadWriteOnce volume, so this is **one
replica, recreated** — the same single-writer discipline as
[vaultwarden](../vaultwarden/).
