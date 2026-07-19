<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# dokuwiki

[DokuWiki](https://www.dokuwiki.org/) — a simple, database-less wiki that stores its
pages as flat files. A plain composable `kurly.http` workload on the official image;
all of its content lives on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local dokuwiki = import 'github.com/metio/kurly/workloads/dokuwiki/server.libsonnet';

kurly.list(dokuwiki())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `dokuwiki` | |
| `image` | `docker.io/dokuwiki/dokuwiki:2025-05-14b` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | all content (`/storage`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the wiki on `:80` — compose an exposure onto it.

## Security and persistence

The nginx + PHP-FPM image starts as **root** and binds `:80`, so this workload
relaxes kurly's non-root and read-only-rootfs defaults while keeping dropped
capabilities and no privilege escalation. The flat-file content lives on a
ReadWriteOnce volume, so this is **one replica, recreated**.
