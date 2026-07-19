<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# homer

[Homer](https://github.com/bastienwirtz/homer) — a simple, static dashboard for your
self-hosted services. A plain composable `kurly.http` workload on the official
image; its configuration and custom assets live on a PersistentVolume, so it needs
no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local homer = import 'github.com/metio/kurly/workloads/homer/server.libsonnet';

kurly.list(homer())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `homer` | |
| `image` | `docker.io/b4bz/homer:v26.4.2` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | assets and `config.yml` (`/www/assets`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the dashboard on `:8080` — compose an exposure onto it. Edit
`/www/assets/config.yml` on the volume to configure it (the image seeds defaults on
first start via `INIT_ASSETS`).

## Persistence

The assets live on a ReadWriteOnce volume, so this is **one replica, recreated** —
the same single-writer discipline as [vaultwarden](../vaultwarden/).
