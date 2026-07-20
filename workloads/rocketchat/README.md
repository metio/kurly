<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# rocketchat

[Rocket.Chat](https://rocket.chat) — a self-hosted, open-source team chat and
collaboration platform. A plain composable `kurly.http` workload on the official image,
backed by an external MongoDB **replica set** (Rocket.Chat requires the oplog).

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local rocketchat = import 'github.com/metio/kurly/workloads/rocketchat/server.libsonnet';

kurly.list(rocketchat(rootUrl='https://chat.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `rocketchat` | |
| `image` | `docker.io/rocketchat/rocket.chat:8.6.1` | |
| `replicas` | `2` | stateless — scale freely |
| `rootUrl` | inferred | the public URL |
| `secretName` | `rocketchat-secrets` | Secret with `MONGO_URL` and `MONGO_OPLOG_URL` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves on `:3000` — compose an exposure onto it. Pairs with a
[mongodb-cluster](../mongodb-cluster/) named `rocketchat-db`.

## Persistence

Uploaded files live in MongoDB (GridFS) by default, so this is **stateless** — a plain
rolling Deployment.
