<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# karakeep

[Karakeep](https://karakeep.app) (formerly Hoarder) — a self-hosted "bookmark
everything" app: save links, notes and images and search them with AI tagging. A plain
composable `kurly.http` workload on the official image; its SQLite database and stored
assets live on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local karakeep = import 'github.com/metio/kurly/workloads/karakeep/server.libsonnet';

kurly.list(karakeep(nextauthUrl='https://bookmarks.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `karakeep` | |
| `image` | `ghcr.io/karakeep-app/karakeep:v0.32.0` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | database and assets (`/data`) |
| `nextauthUrl` | inferred | the public URL |
| `meiliAddr` | `http://meilisearch:7700` | Meilisearch endpoint |
| `browserWebUrl` | `http://chrome:9222` | headless-Chrome endpoint |
| `secretName` | `karakeep-secrets` | `NEXTAUTH_SECRET`, `MEILI_MASTER_KEY`, AI provider keys (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves on `:3000` — compose an exposure onto it.

## Companions

Karakeep expects two side services it does not bundle here — a **Meilisearch** instance
for full-text search (`MEILI_ADDR` + `MEILI_MASTER_KEY`) and a **headless Chrome** for
fetching page content (`BROWSER_WEB_URL`). Run them alongside and point the env at them;
the web app starts without them, but search and crawling stay degraded until they are
reachable.

## Persistence

The SQLite database and assets live on a ReadWriteOnce volume, so this is **one replica,
recreated**.
