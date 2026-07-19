<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# microbin

[MicroBin](https://github.com/szabodanika/microbin) — a tiny, self-contained
pastebin and file-sharing service. A plain composable `kurly.http` workload that
keeps its pastes and uploaded files on a PersistentVolume, so it needs no external
database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local microbin = import 'github.com/metio/kurly/workloads/microbin/server.libsonnet';

kurly.list(microbin())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `microbin` | |
| `image` | `docker.io/danielszabo99/microbin:v2.1.4` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | pastes and files (`/app/microbin_data`) |
| `env` | `{}` | extra `MICROBIN_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:8080` — compose an exposure onto it.

## Persistence

The pastes and files live on a ReadWriteOnce volume, so this is **one replica,
recreated** — the same single-writer discipline as [vaultwarden](../vaultwarden/).
