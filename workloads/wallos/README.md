<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wallos

[Wallos](https://github.com/ellite/Wallos) — a self-hosted subscription tracker and
budgeting tool: track recurring subscriptions, costs and renewal dates in one place. A plain
composable `kurly.http` workload on the official image; its SQLite database lives on a
PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wallos = import 'github.com/metio/kurly/workloads/wallos/server.libsonnet';
kurly.list(wallos())
```

Database at `/var/www/html/db` on a ReadWriteOnce volume, so **one replica, recreated**.
Serves on `:80`.
