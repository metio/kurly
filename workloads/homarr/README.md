<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# homarr

[Homarr](https://homarr.dev) — a sleek, self-hosted dashboard for your homelab: pin
your services, search across them, and watch their status in one place. A plain
composable `kurly.http` workload on the official image; its SQLite database and config
live on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local homarr = import 'github.com/metio/kurly/workloads/homarr/server.libsonnet';

kurly.list(homarr())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `homarr` | |
| `image` | `ghcr.io/homarr-labs/homarr:v1.71.0` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | data (`/appdata`) |
| `secretName` | `homarr-secrets` | Secret with `SECRET_ENCRYPTION_KEY` (64-char hex, envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the dashboard on `:7575` — compose an exposure onto it.

## Persistence

The SQLite database lives on a ReadWriteOnce volume, so this is **one replica,
recreated**.
