<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# automatisch

[Automatisch](https://automatisch.io) — a self-hosted, open-source business-automation /
workflow tool, an open alternative to Zapier. Two stages on the official image, backed
by an external PostgreSQL and Redis: a **web server** and a **background worker** that
runs the flow executions the server enqueues onto Redis.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local server = import 'github.com/metio/kurly/workloads/automatisch/server.libsonnet';
local worker = import 'github.com/metio/kurly/workloads/automatisch/worker.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='automatisch-db', database='automatisch')).items,
  kurly.list(server()).items,
  kurly.list(worker()).items,
]))
```

Both stages read the PostgreSQL/Redis connection and the `ENCRYPTION_KEY` /
`WEBHOOK_SECRET_KEY` / `APP_SECRET_KEY` from a shared Secret (`automatisch-secrets`) via
`envFrom` — kurly authors **no Secret**. The server serves on `:3000`; the worker has no
Service. Flow state lives in PostgreSQL and Redis, so both stages are **stateless**.
