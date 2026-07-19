<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# linkding

[linkding](https://github.com/sissbruecker/linkding) — a minimal, self-hosted
bookmark manager. A plain composable `kurly.http` workload that keeps its bookmarks
in a SQLite database on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local linkding = import 'github.com/metio/kurly/workloads/linkding/server.libsonnet';

kurly.list(linkding())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `linkding` | |
| `image` | `docker.io/sissbruecker/linkding:1.45.0` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the SQLite data volume (`/etc/linkding/data`) |
| `env` | `{}` | extra `LD_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:9090` — compose an exposure onto it. Point
`LD_DB_ENGINE` at an external PostgreSQL through `env` to scale past the single
SQLite writer.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica, recreated**
— the same single-writer discipline as [vaultwarden](../vaultwarden/).
