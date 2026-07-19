<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# readeck

[Readeck](https://readeck.org/) — a self-hosted read-it-later and web-bookmarking
tool that saves clean, readable copies of pages. A plain composable `kurly.http`
workload that keeps its bookmarks and saved articles in SQLite on a
PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local readeck = import 'github.com/metio/kurly/workloads/readeck/server.libsonnet';

kurly.list(readeck())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `readeck` | |
| `image` | `codeberg.org/readeck/readeck:0.22.3` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | database and saved pages (`/readeck`) |
| `env` | `{}` | extra `READECK_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:8000` — compose an exposure onto it.

## Persistence

The SQLite database and saved pages live on a ReadWriteOnce volume, so this is **one
replica, recreated** — the same single-writer discipline as
[vaultwarden](../vaultwarden/).
