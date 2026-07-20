<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# teable

[Teable](https://teable.io) — a self-hosted, no-code database built on PostgreSQL that presents as a spreadsheet, an Airtable alternative. A `kurly.http` workload on the official image, backed by an external PostgreSQL (and Redis for realtime/caching).

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local teable = import 'github.com/metio/kurly/workloads/teable/server.libsonnet';
kurly.list(teable(publicOrigin='https://teable.example.com'))
```

Stateless with S3 attachment storage — a plain rolling Deployment. Serves on `:3000`.

**Secrets:** Teable reads `PRISMA_DATABASE_URL`, `BACKEND_CACHE_REDIS_URI`, `SECRET_KEY` and its mail/storage settings from the environment. kurly authors no Secret; provide one (via `secretName`) holding them. The defaults pair with a `cnpg-cluster` named `teable-db` and a Redis.
