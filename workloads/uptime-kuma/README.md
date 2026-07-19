<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# uptime-kuma

[Uptime Kuma](https://github.com/louislam/uptime-kuma) — self-hosted uptime
monitoring and status pages. A plain composable `kurly.http` workload that keeps
its checks, history, and settings in a SQLite database on a PersistentVolume, so it
needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local uptimeKuma = import 'github.com/metio/kurly/workloads/uptime-kuma/server.libsonnet';

kurly.list(uptimeKuma())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `uptime-kuma` | |
| `image` | `docker.io/louislam/uptime-kuma:1.23.16` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the SQLite data volume |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the dashboard and status pages on `:3001` — compose an exposure onto it:

```jsonnet
kurly.listOf([
  uptimeKuma()
  + kurly.expose.ownGateway('status.example.com', 'istio', tls='uptime-kuma-tls'),
  kurly.certificate('uptime-kuma-tls', ['status.example.com'], 'letsencrypt-prod'),
])
```

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica, recreated**
(never rolled) to keep two pods off the file — the same single-writer discipline as
[vaultwarden](../vaultwarden/).
