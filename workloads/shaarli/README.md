<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# shaarli

[Shaarli](https://github.com/shaarli/Shaarli) — a self-hosted, database-free bookmarking
and link-sharing app: a personal, minimalist "delicious" you fully own. A plain composable
`kurly.http` workload on the official image; because Shaarli is flat-file, its data lives
on a PersistentVolume — no external database.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local shaarli = import 'github.com/metio/kurly/workloads/shaarli/server.libsonnet';
kurly.list(shaarli())
```

Data at `/var/www/shaarli/data` on a ReadWriteOnce volume, so **one replica, recreated**.
Serves on `:80`.
