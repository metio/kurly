<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# audiobookshelf

[Audiobookshelf](https://github.com/advplyr/audiobookshelf) — a self-hosted
audiobook and podcast server. A plain composable `kurly.http` workload on the
official image: it keeps its config, metadata, and library on a PersistentVolume, so
it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local audiobookshelf = import 'github.com/metio/kurly/workloads/audiobookshelf/server.libsonnet';

kurly.list(audiobookshelf())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `audiobookshelf` | |
| `image` | `ghcr.io/advplyr/audiobookshelf:2.35.1` | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | config, metadata, and library |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:80` — compose an exposure onto it. Put your audiobooks
and podcasts under `/audiobooks` on the volume.

## Persistence

The config and metadata live on a ReadWriteOnce volume, so this is **one replica,
recreated** — the same single-writer discipline as [vaultwarden](../vaultwarden/).
