<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# qdrant

[Qdrant](https://qdrant.tech) — a self-hosted vector database and similarity-search engine for embeddings (AI/semantic-search and RAG). A `kurly.http` workload on the official image; collections on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local qdrant = import 'github.com/metio/kurly/workloads/qdrant/server.libsonnet';
kurly.list(qdrant())
```

gRPC on `:6334` needs an extra Service. Collections at `/qdrant/storage` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the REST API on `:6333`.
