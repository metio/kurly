<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# znc

[ZNC](https://znc.in/) — an IRC bouncer that stays connected to IRC and replays
what you missed. A plain composable `kurly.http` workload on the official image
that keeps its configuration, module data, and buffers on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local znc = import 'github.com/metio/kurly/workloads/znc/server.libsonnet';

kurly.list(znc())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `znc` | |
| `image` | `docker.io/library/znc:1.10.2` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the data volume (`/znc-data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves IRC and the web admin on `:6697` — route it as TCP through a LoadBalancer or
a Gateway TCPRoute.

## Configuration

ZNC needs a `znc.conf` (with user credentials) at `/znc-data/configs/znc.conf`
**before it starts**. Generate one with `znc --makeconf` and place it on the volume,
or mount it from a Secret (kurly mints none — it holds passwords).

## Persistence

The configuration and buffers live on a ReadWriteOnce volume, so this is **one
replica, recreated** (never rolled) to keep two pods off the files.
