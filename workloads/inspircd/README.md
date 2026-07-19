<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# inspircd

[InspIRCd](https://www.inspircd.org/) — a modular IRC daemon. A plain composable
`kurly.http` workload on the official image that keeps its runtime data (logs, TLS
material) on a PersistentVolume and reads its configuration from a mounted config.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local inspircd = import 'github.com/metio/kurly/workloads/inspircd/server.libsonnet';

kurly.list(inspircd())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `inspircd` | |
| `image` | `docker.io/inspircd/inspircd-docker:4.11.0` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the runtime data volume (`/inspircd/data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves IRC-over-TLS on `:6697` — route it as TCP through a LoadBalancer or a Gateway
TCPRoute.

## Configuration

InspIRCd needs its configuration at `/inspircd/conf` (an `inspircd.conf` and the
files it includes). Mount it with `kurly.config`, or from a Secret (kurly mints
none) where it carries oper passwords or link credentials.

## Persistence

The runtime data lives on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled) to keep two pods off the files.
