<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# kanboard

[Kanboard](https://kanboard.org/) — a minimalist kanban project-management board. A
plain composable `kurly.http` workload on the official image that keeps its board
data in a SQLite database and uploaded files on a PersistentVolume by default, so
it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local kanboard = import 'github.com/metio/kurly/workloads/kanboard/server.libsonnet';

kurly.list(kanboard())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `kanboard` | |
| `image` | `docker.io/kanboard/kanboard:v1.2.52` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the data volume (`/var/www/app/data`) |
| `env` | `{}` | extra environment (`DATABASE_URL` for external Postgres, `PLUGIN_INSTALLER`, …) |
| `resources` / `labels` / `annotations` | | |

Serves the web UI on `:80` — compose an exposure onto it:

```jsonnet
kurly.listOf([
  kanboard()
  + kurly.expose.ownGateway('board.example.com', 'istio', tls='kanboard-tls'),
  kurly.certificate('kanboard-tls', ['board.example.com'], 'letsencrypt-prod'),
])
```

Point `DATABASE_URL` at an external PostgreSQL (the [cnpg-cluster](../cnpg-cluster/)
workload) to scale past the single SQLite writer.

## Security and persistence

The nginx + PHP-FPM image starts as **root** and binds `:80`, so this workload
relaxes kurly's non-root and read-only-rootfs defaults while keeping dropped
capabilities and no privilege escalation. The SQLite database lives on a
ReadWriteOnce volume, so this is **one replica, recreated**.
