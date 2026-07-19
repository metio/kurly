<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# navidrome

[Navidrome](https://github.com/navidrome/navidrome) — a modern music server and
streamer, compatible with Subsonic/Airsonic clients. A plain composable `kurly.http`
workload on the official image: it keeps its database on a PersistentVolume and reads
your music library from it, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local navidrome = import 'github.com/metio/kurly/workloads/navidrome/server.libsonnet';

kurly.list(navidrome())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `navidrome` | |
| `image` | `docker.io/deluan/navidrome:0.63.2` | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | database (`/data`) and music (`/music`) |
| `env` | `{}` | extra `ND_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and Subsonic API on `:4533` — compose an exposure onto it. Put your
music under `/music` on the volume.

## Persistence

The database lives on a ReadWriteOnce volume, so this is **one replica, recreated** —
the same single-writer discipline as [vaultwarden](../vaultwarden/).
