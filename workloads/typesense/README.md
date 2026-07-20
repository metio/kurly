<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# typesense

[Typesense](https://typesense.org) — a fast, typo-tolerant, self-hosted search engine with a clean API. A `kurly.http` workload on the official image; data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local typesense = import 'github.com/metio/kurly/workloads/typesense/server.libsonnet';
kurly.list(typesense())
```

`TYPESENSE_API_KEY` comes from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8108`.
