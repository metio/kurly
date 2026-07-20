<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# meilisearch

[Meilisearch](https://www.meilisearch.com) — a fast, typo-tolerant, self-hosted search engine with a simple REST API. A `kurly.http` workload on the official image; indexes on a PersistentVolume. The search companion several apps expect (e.g. [karakeep](../karakeep/)).

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local meilisearch = import 'github.com/metio/kurly/workloads/meilisearch/server.libsonnet';
kurly.list(meilisearch())
```

`MEILI_MASTER_KEY` comes from a Secret via `envFrom` — kurly authors **no Secret**. Indexes at `/meili_data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:7700`.
