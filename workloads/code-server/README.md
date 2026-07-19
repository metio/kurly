<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# code-server

[code-server](https://github.com/coder/code-server) — VS Code running in the
browser, on a remote server. A plain composable `kurly.http` workload on the
official image: your projects, extensions, and settings live on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local codeServer = import 'github.com/metio/kurly/workloads/code-server/server.libsonnet';

kurly.list(codeServer())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `code-server` | |
| `image` | `docker.io/codercom/code-server:4.129.0` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | workspace, extensions, settings (`/home/coder`) |
| `secretName` | `code-server-secrets` | Secret with `PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the editor on `:8080` — compose an exposure onto it.

## Auth and persistence

code-server reads its `PASSWORD` (or `HASHED_PASSWORD`) from the environment. kurly
authors **no Secret** — provide `code-server-secrets` holding `PASSWORD`, pulled in
via `envFrom` (fill it with [`kurly.externalSecret`](../../main.libsonnet)). Your
workspace lives on a ReadWriteOnce volume, so this is **one replica, recreated**.
