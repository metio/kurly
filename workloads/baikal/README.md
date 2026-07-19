<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# baikal

[Baïkal](https://github.com/sabre-io/Baikal) — a lightweight CalDAV + CardDAV
server built on [sabre/dav](https://sabre.io/). A plain composable `kurly.http`
workload on the maintained [ckulka](https://github.com/ckulka/baikal-docker) image
that keeps its configuration and SQLite database on a PersistentVolume, so it needs
no external database by default.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local baikal = import 'github.com/metio/kurly/workloads/baikal/server.libsonnet';

kurly.list(baikal())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `baikal` | |
| `image` | `docker.io/ckulka/baikal:0.10.1-nginx` | the nginx variant |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the data volume (DB at `/Specific`, config at `/config`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the admin UI and CalDAV/CardDAV on `:80` — compose an exposure onto it:

```jsonnet
kurly.listOf([
  baikal()
  + kurly.expose.ownGateway('dav.example.com', 'istio', tls='baikal-tls'),
  kurly.certificate('baikal-tls', ['dav.example.com'], 'letsencrypt-prod'),
])
```

Point Baïkal at an external MySQL/PostgreSQL through its setup wizard to scale past
the single SQLite writer.

## Security and persistence

The nginx + PHP-FPM image starts as **root** and binds `:80`, so this workload
relaxes kurly's non-root and read-only-rootfs defaults while keeping dropped
capabilities and no privilege escalation. Both the database and the generated
config live on one ReadWriteOnce volume, so this is **one replica, recreated**.
