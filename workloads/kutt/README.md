<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# kutt

[Kutt](https://kutt.it) — a free, self-hosted modern URL shortener with custom domains, link analytics and an API. A `kurly.http` workload on the official image, backed by an external PostgreSQL and Redis.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local kutt = import 'github.com/metio/kurly/workloads/kutt/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(cnpg(name='kutt-db', database='kutt')).items,
  kurly.list(kutt()).items,
]))
```

The PostgreSQL/Redis connection, `JWT_SECRET` and `DEFAULT_DOMAIN` come from a Secret via `envFrom` — kurly authors **no Secret**. Stateless (links live in PostgreSQL). Serves on `:3000`.
