<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# stirling-pdf

[Stirling-PDF](https://github.com/Stirling-Tools/Stirling-PDF) — a locally-hosted
web toolkit for splitting, merging, converting, and editing PDFs. A plain composable
`kurly.http` workload on the official image: it processes files in memory and keeps
its configuration on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local stirling = import 'github.com/metio/kurly/workloads/stirling-pdf/server.libsonnet';

kurly.list(stirling())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `stirling-pdf` | |
| `image` | `docker.io/stirlingtools/stirling-pdf:2.14.2` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | configuration and custom files (`/configs`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:8080` — compose an exposure onto it.

## Security and persistence

The image runs LibreOffice and other tools and writes across the root filesystem, so
this workload relaxes kurly's read-only-rootfs default while keeping non-root,
dropped capabilities, and no privilege escalation. The configuration lives on a
ReadWriteOnce volume, so this is **one replica, recreated**.
