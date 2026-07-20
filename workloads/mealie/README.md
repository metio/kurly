<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mealie

[Mealie](https://mealie.io) — a self-hosted recipe manager and meal planner with a recipe
scraper, shopping lists and a REST API. A plain composable `kurly.http` workload on the
official image; with the default SQLite backend its database and uploaded assets live on
a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mealie = import 'github.com/metio/kurly/workloads/mealie/server.libsonnet';
kurly.list(mealie(baseUrl='https://recipes.example.com'))
```

Point Mealie at an external PostgreSQL (`DB_ENGINE=postgres` plus the `POSTGRES_*`
connection) to scale past the single SQLite writer. Data at `/app/data` on a ReadWriteOnce
volume, so **one replica, recreated**. Serves on `:9000`.
