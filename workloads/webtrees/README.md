<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# webtrees

[webtrees](https://www.webtrees.net) — a self-hosted, collaborative online genealogy application. A `kurly.http` workload on the community image, backed by an external MySQL/MariaDB, with data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local webtrees = import 'github.com/metio/kurly/workloads/webtrees/server.libsonnet';
local mysql = import 'github.com/metio/kurly/workloads/mysql-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(mysql(name='webtrees-db')).items,
  kurly.list(webtrees(baseUrl='https://tree.example.com')).items,
]))
```

The `DB_*` credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/var/www/webtrees/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
