<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wekan

[Wekan](https://wekan.github.io) — a self-hosted, open-source kanban board, à la
Trello. A plain composable `kurly.http` workload on the official image, backed by an
external MongoDB.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wekan = import 'github.com/metio/kurly/workloads/wekan/server.libsonnet';

kurly.list(wekan(rootUrl='https://boards.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wekan` | |
| `image` | `docker.io/wekan/wekan:v10.03` | |
| `replicas` | `2` | stateless — scale freely |
| `rootUrl` | inferred | the public URL |
| `secretName` | `wekan-secrets` | Secret with `MONGO_URL` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves on `:8080` — compose an exposure onto it. Pairs with a
[mongodb-cluster](../mongodb-cluster/) named `wekan-db`.

## Persistence

Card attachments live in MongoDB (GridFS) by default, so this is **stateless** — a
plain rolling Deployment.
