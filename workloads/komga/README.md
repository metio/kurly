<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# komga

[Komga](https://github.com/gotson/komga) — a media server for comics, manga, and
digital books. A plain composable `kurly.http` workload on the official image: it
keeps its database and thumbnails and reads its library from a PersistentVolume, so
it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local komga = import 'github.com/metio/kurly/workloads/komga/server.libsonnet';

kurly.list(komga())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `komga` | |
| `image` | `docker.io/gotson/komga:1.25.0` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | database (`/config`) and library (`/books`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web UI, OPDS, and API on `:25600` — compose an exposure onto it. Put your
comic/book library under `/books` on the volume.

## Security and persistence

The Java app writes temp files to the root filesystem, so this workload relaxes
kurly's read-only-rootfs default while keeping non-root, dropped capabilities, and no
privilege escalation. The database lives on a ReadWriteOnce volume, so this is **one
replica, recreated**.
