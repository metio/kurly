<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# commafeed

[CommaFeed](https://github.com/Athou/commafeed) — a self-hosted Google Reader-style
RSS/Atom feed reader. A plain composable `kurly.http` workload on the official image:
the H2 variant keeps its feeds and articles in an embedded database on a
PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local commafeed = import 'github.com/metio/kurly/workloads/commafeed/server.libsonnet';

kurly.list(commafeed())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `commafeed` | |
| `image` | `docker.io/athou/commafeed:7.2.0-h2` | the H2 (embedded-DB) variant |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the embedded database (`/commafeed/data`) |
| `env` | `{}` | extra `CF_APP_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:8082` — compose an exposure onto it.

## Persistence

The embedded H2 database lives on a ReadWriteOnce volume, so this is **one replica,
recreated** — the same single-writer discipline as [vaultwarden](../vaultwarden/). Use
the PostgreSQL image variant (`athou/commafeed:<version>-postgresql`) and point
`CF_APP_DATABASE` at a [cnpg-cluster](../cnpg-cluster/) to scale past the embedded DB.
