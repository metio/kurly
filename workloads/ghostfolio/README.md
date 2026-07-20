<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ghostfolio

[Ghostfolio](https://ghostfol.io) — a self-hosted, open-source wealth-management and portfolio tracker for stocks, ETFs, crypto and more. A `kurly.http` workload on the official image, backed by an external PostgreSQL and Redis.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ghostfolio = import 'github.com/metio/kurly/workloads/ghostfolio/server.libsonnet';
kurly.list(ghostfolio())
```

Stateless — a plain rolling Deployment. Serves on `:3333`.

**Secrets:** Ghostfolio reads `DATABASE_URL`, the Redis settings, `ACCESS_TOKEN_SALT` and `JWT_SECRET_KEY` from the environment. kurly authors no Secret; provide one (via `secretName`) holding them. The defaults pair with a `cnpg-cluster` named `ghostfolio-db` and a Redis.
