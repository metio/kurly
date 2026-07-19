<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# trilium

[TriliumNext Notes](https://github.com/TriliumNext/Trilium) — a hierarchical
note-taking application for building personal knowledge bases. A plain composable
`kurly.http` workload that keeps its notes in a SQLite database on a
PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local trilium = import 'github.com/metio/kurly/workloads/trilium/server.libsonnet';

kurly.list(trilium())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `trilium` | |
| `image` | `ghcr.io/triliumnext/trilium:v0.104.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the SQLite data volume (`/home/node/trilium-data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web app and sync API on `:8080` — compose an exposure onto it.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica, recreated**
— the same single-writer discipline as [vaultwarden](../vaultwarden/).
