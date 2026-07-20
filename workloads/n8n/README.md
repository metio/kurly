<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# n8n

[n8n](https://github.com/n8n-io/n8n) — a fair-code workflow-automation tool: connect
apps and automate tasks with a visual editor. A plain composable `kurly.http`
workload that keeps its workflows, credentials, and encryption key in a SQLite
database on a PersistentVolume by default, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local n8n = import 'github.com/metio/kurly/workloads/n8n/server.libsonnet';

kurly.list(n8n(host='n8n.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `n8n` | |
| `image` | `docker.io/n8nio/n8n:2.31.4` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the SQLite data volume (`/home/node/.n8n`) |
| `host` | inferred | the public hostname (webhooks need it) |
| `env` | `{}` | extra `N8N_*` / `DB_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the editor, API, and webhooks on `:5678` — compose an exposure onto it.

## Persistence

The SQLite database and the auto-generated encryption key live on a ReadWriteOnce
volume, so this is **one replica, recreated** — the same single-writer discipline as
[vaultwarden](../vaultwarden/). Point `DB_TYPE` at an external PostgreSQL and set
`N8N_ENCRYPTION_KEY` (from a Secret, via `env`) to scale out.
