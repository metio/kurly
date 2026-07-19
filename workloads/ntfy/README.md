<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ntfy

[ntfy](https://ntfy.sh/) — send push notifications to your phone or desktop over
simple HTTP. A plain composable `kurly.http` workload that keeps its message cache
and user database in SQLite on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ntfy = import 'github.com/metio/kurly/workloads/ntfy/server.libsonnet';

kurly.list(ntfy(baseUrl='https://ntfy.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `ntfy` | |
| `image` | `docker.io/binwiederhier/ntfy:v2.26.0` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | cache, auth db, attachments (`/var/lib/ntfy`) |
| `baseUrl` | inferred | the public URL (needed for the web app, attachments, iOS) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and publish/subscribe API on `:80` — compose an exposure onto it.

## Persistence

The SQLite cache and auth database live on a ReadWriteOnce volume, so this is **one
replica, recreated** — the same single-writer discipline as
[vaultwarden](../vaultwarden/).
