<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# planka

[Planka](https://planka.app) — a self-hosted, real-time kanban board for teams, an open alternative to Trello. A `kurly.http` workload on the official image, backed by an external PostgreSQL, with uploads in S3-compatible object storage.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local planka = import 'github.com/metio/kurly/workloads/planka/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(cnpg(name='planka-db', database='planka')).items,
  kurly.list(planka(baseUrl='https://boards.example.com')).items,
]))
```

`DATABASE_URL`, `SECRET_KEY`, the `S3_*` settings and the admin credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Uploads go to S3 (pair with [seaweedfs](../seaweedfs/)), so this is **stateless**. For local-disk uploads instead, compose ReadWriteMany volumes onto the three upload paths and drop the S3 settings. Serves on `:1337`.
