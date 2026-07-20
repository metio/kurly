<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# openproject

[OpenProject](https://www.openproject.org) — a self-hosted, open-source project-management and collaboration suite: work packages, Gantt charts, agile boards, wikis and time tracking. A `kurly.http` workload on the official image, backed by an external PostgreSQL, with uploaded assets on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local openproject = import 'github.com/metio/kurly/workloads/openproject/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(cnpg(name='openproject-db', database='openproject')).items,
  kurly.list(openproject(hostName='projects.example.com')).items,
]))
```

`DATABASE_URL`, `SECRET_KEY_BASE` and host settings come from a Secret via `envFrom` — kurly authors **no Secret**. A production deployment also wants a memcached. Assets at `/var/openproject/assets` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
