<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# answer

[Apache Answer](https://github.com/apache/answer) — a self-hosted Q&A platform for
building a community knowledge base, à la Stack Overflow. A plain composable
`kurly.http` workload on the official image: with the SQLite backend its data and
uploads live on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local answer = import 'github.com/metio/kurly/workloads/answer/server.libsonnet';

kurly.list(answer())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `answer` | |
| `image` | `docker.io/apache/answer:v2.0.1` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | data and uploads (`/data`) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:80` — compose an exposure onto it.

## Persistence

The SQLite database and uploads live on a ReadWriteOnce volume, so this is **one
replica, recreated** — the same single-writer discipline as
[vaultwarden](../vaultwarden/). Configure an external PostgreSQL/MySQL through the
installer to scale past the single SQLite writer.
