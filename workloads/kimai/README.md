<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# kimai

[Kimai](https://www.kimai.org) — a self-hosted, professional time-tracking application for freelancers and teams. A `kurly.http` workload on the official Apache image, backed by an external MySQL/MariaDB.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local kimai = import 'github.com/metio/kurly/workloads/kimai/server.libsonnet';
local mysql = import 'github.com/metio/kurly/workloads/mysql-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(mysql(name='kimai-db')).items,
  kurly.list(kimai()).items,
]))
```

`DATABASE_URL` and `APP_SECRET` come from a Secret via `envFrom` — kurly authors **no Secret**. Stateless (timesheets live in MySQL). Serves on `:8001`.
