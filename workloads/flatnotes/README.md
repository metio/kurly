<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# flatnotes

[flatnotes](https://github.com/dullage/flatnotes) — a self-hosted, database-less
note-taking app that stores everything as flat markdown files. A plain composable
`kurly.http` workload: your notes live on a PersistentVolume, so it needs no external
database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local flatnotes = import 'github.com/metio/kurly/workloads/flatnotes/server.libsonnet';

kurly.list(flatnotes())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `flatnotes` | |
| `image` | `docker.io/dullage/flatnotes:v5.5.4` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the markdown files (`/data`) |
| `secretName` | `flatnotes-secrets` | Secret with `FLATNOTES_USERNAME`, `FLATNOTES_PASSWORD`, `FLATNOTES_SECRET_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:8080` — compose an exposure onto it.

## Auth and persistence

flatnotes reads its auth type, credentials, and secret key from the environment.
kurly authors **no Secret** — provide `flatnotes-secrets` holding the username,
password, and secret key, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The markdown files live on a
ReadWriteOnce volume, so this is **one replica, recreated**.
