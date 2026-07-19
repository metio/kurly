<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# silverbullet

[SilverBullet](https://github.com/silverbulletmd/silverbullet) — an extensible,
self-hosted markdown notebook / personal knowledge base. A plain composable
`kurly.http` workload: your notes are plain markdown files on a PersistentVolume, so
it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local silverbullet = import 'github.com/metio/kurly/workloads/silverbullet/server.libsonnet';

kurly.list(silverbullet())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `silverbullet` | |
| `image` | `ghcr.io/silverbulletmd/silverbullet:2.9.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the markdown space (`/space`) |
| `secretName` | `silverbullet-secrets` | Secret with `SB_USER` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the editor on `:3000` — compose an exposure onto it.

## Auth and persistence

SilverBullet reads `SB_USER` (`user:password`) from the environment. kurly authors
**no Secret** — provide `silverbullet-secrets` holding `SB_USER`, pulled in via
`envFrom` (fill it with [`kurly.externalSecret`](../../main.libsonnet)). The markdown
space lives on a ReadWriteOnce volume, so this is **one replica, recreated**.
