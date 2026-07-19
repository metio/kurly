<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# kavita

[Kavita](https://github.com/Kareadita/Kavita) — a fast, cross-platform reading
server for comics, manga, and ebooks. A plain composable `kurly.http` workload on
the official image: it keeps its database and settings and reads its library from a
PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local kavita = import 'github.com/metio/kurly/workloads/kavita/server.libsonnet';

kurly.list(kavita())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `kavita` | |
| `image` | `docker.io/jvmilazz0/kavita:0.9.0.2` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | database (`/kavita/config`) and library (`/library`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web UI, OPDS, and API on `:5000` — compose an exposure onto it. Put your
library under `/library` on the volume.

## Security and persistence

The .NET app writes temp files to the root filesystem, so this workload relaxes
kurly's read-only-rootfs default while keeping non-root, dropped capabilities, and no
privilege escalation. The database lives on a ReadWriteOnce volume, so this is **one
replica, recreated**.
