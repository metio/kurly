<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# yourls

[YOURLS](https://yourls.org) — Your Own URL Shortener: a small, self-hosted PHP app for your own short links with stats and plugins. A `kurly.http` workload on the official image, backed by an external MySQL/MariaDB.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local yourls = import 'github.com/metio/kurly/workloads/yourls/server.libsonnet';
local mysql = import 'github.com/metio/kurly/workloads/mysql-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(mysql(name='yourls-db')).items,
  kurly.list(yourls(site='https://s.example.com')).items,
]))
```

The `YOURLS_DB_*` and admin `YOURLS_USER`/`YOURLS_PASS` come from a Secret via `envFrom` — kurly authors **no Secret**. Stateless (links live in MySQL). Serves on `:80`.
