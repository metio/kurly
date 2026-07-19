<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# homebox

[Homebox](https://github.com/sysadminsmedia/homebox) — a simple home/household
inventory and asset manager. A plain composable `kurly.http` workload on the
**rootless** image that keeps its inventory in a SQLite database and uploaded
attachments on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local homebox = import 'github.com/metio/kurly/workloads/homebox/server.libsonnet';

kurly.list(homebox())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `homebox` | |
| `image` | `ghcr.io/sysadminsmedia/homebox:0.26.2-rootless` | the rootless variant |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the data volume (`/data`) |
| `env` | `{}` | extra `HBOX_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:7745` — compose an exposure onto it:

```jsonnet
kurly.listOf([
  homebox()
  + kurly.expose.ownGateway('inventory.example.com', 'istio', tls='homebox-tls'),
  kurly.certificate('homebox-tls', ['inventory.example.com'], 'letsencrypt-prod'),
])
```

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica, recreated**
(never rolled) to keep two pods off the file — the same single-writer discipline as
[vaultwarden](../vaultwarden/).
