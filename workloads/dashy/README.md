<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# dashy

[Dashy](https://github.com/Lissy93/dashy) — a highly customizable, self-hosted
dashboard for your services. A plain composable `kurly.http` workload on the
official image; its configuration lives on a PersistentVolume, so it needs no
external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local dashy = import 'github.com/metio/kurly/workloads/dashy/server.libsonnet';

kurly.list(dashy())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `dashy` | |
| `image` | `docker.io/lissy93/dashy:4.4.7` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | configuration (`/app/user-data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the dashboard on `:8080` — compose an exposure onto it. Edit
`/app/user-data/conf.yml` on the volume to configure it.

## Security and persistence

The image rebuilds its assets on a config change and writes across the root
filesystem, so this workload relaxes kurly's read-only-rootfs default while keeping
non-root, dropped capabilities, and no privilege escalation. The configuration lives
on a ReadWriteOnce volume, so this is **one replica, recreated**.
