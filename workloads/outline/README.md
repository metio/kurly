<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# outline

[Outline](https://www.getoutline.com) — a fast, collaborative, self-hosted team knowledge base and wiki with real-time editing. A `kurly.http` workload on the official image, backed by an external PostgreSQL, Redis and S3-compatible object storage.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local outline = import 'github.com/metio/kurly/workloads/outline/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(cnpg(name='outline-db', database='outline')).items,
  kurly.list(outline(url='https://wiki.example.com')).items,
]))
```

`DATABASE_URL`, `REDIS_URL`, `SECRET_KEY`, `UTILS_SECRET`, the S3 settings and an auth provider come from a Secret via `envFrom` — kurly authors **no Secret**. Uploads go to S3 (pair with [seaweedfs](../seaweedfs/)). Stateless. Serves on `:3000`.
