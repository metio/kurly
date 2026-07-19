<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# memos

[Memos](https://github.com/usememos/memos) — a lightweight, self-hosted notes and
micro-blogging service. A plain composable `kurly.http` workload that keeps its
notes in a SQLite database on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local memos = import 'github.com/metio/kurly/workloads/memos/server.libsonnet';

kurly.list(memos())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `memos` | |
| `image` | `docker.io/neosmemo/memos:0.29.1` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the SQLite data volume (`/var/opt/memos`) |
| `env` | `{}` | extra `MEMOS_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:5230` — compose an exposure onto it. Point
`MEMOS_DRIVER` at an external PostgreSQL through `env` to scale past the single
SQLite writer.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica, recreated**
— the same single-writer discipline as [vaultwarden](../vaultwarden/).
