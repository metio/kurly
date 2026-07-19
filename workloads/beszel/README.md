<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# beszel

[Beszel](https://github.com/henrygd/beszel) — a lightweight server-monitoring
dashboard. This workload is the **hub**: a plain composable `kurly.http` workload
that keeps its data in SQLite on a PersistentVolume, so it needs no external
database. Beszel agents run on the machines you monitor and report to this hub.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local beszel = import 'github.com/metio/kurly/workloads/beszel/server.libsonnet';

kurly.list(beszel())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `beszel` | |
| `image` | `ghcr.io/henrygd/beszel/beszel:0.18.7` | the hub image |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the SQLite data volume (`/beszel_data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:8090` — compose an exposure onto it.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica, recreated**
— the same single-writer discipline as [vaultwarden](../vaultwarden/).
