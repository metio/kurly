<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# redmine

[Redmine](https://www.redmine.org) — a mature, self-hosted project-management web app: issue tracking, wikis, forums, Gantt charts and time tracking. A `kurly.http` workload on the official image, backed by an external MySQL/MariaDB or PostgreSQL, with uploaded files on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local redmine = import 'github.com/metio/kurly/workloads/redmine/server.libsonnet';
local mysql = import 'github.com/metio/kurly/workloads/mysql-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(mysql(name='redmine-db')).items,
  kurly.list(redmine()).items,
]))
```

The database connection and `REDMINE_SECRET_KEY_BASE` come from a Secret via `envFrom` — kurly authors **no Secret**. Files at `/usr/src/redmine/files` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:3000`.
