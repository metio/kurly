<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gotify

[Gotify](https://gotify.net/) — a simple server for sending and receiving push
notifications. A plain composable `kurly.http` workload that keeps its messages,
apps, and clients in a SQLite database on a PersistentVolume, so it needs no
external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gotify = import 'github.com/metio/kurly/workloads/gotify/server.libsonnet';

kurly.list(gotify())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `gotify` | |
| `image` | `docker.io/gotify/server:3.0.0` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the SQLite data volume (`/app/data`) |
| `env` | `{}` | extra `GOTIFY_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:80` — compose an exposure onto it.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica, recreated**
— the same single-writer discipline as [vaultwarden](../vaultwarden/).
