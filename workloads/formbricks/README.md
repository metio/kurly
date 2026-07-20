<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# formbricks

[Formbricks](https://formbricks.com) — a self-hosted, open-source experience-management and survey platform. A `kurly.http` workload on the official image, backed by an external PostgreSQL.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local formbricks = import 'github.com/metio/kurly/workloads/formbricks/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(cnpg(name='formbricks-db', database='formbricks')).items,
  kurly.list(formbricks(webappUrl='https://surveys.example.com')).items,
]))
```

`DATABASE_URL`, `NEXTAUTH_SECRET` and `ENCRYPTION_KEY` come from a Secret via `envFrom` — kurly authors **no Secret**. Stateless. Serves on `:3000`.
