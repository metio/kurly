<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pgadmin

[pgAdmin 4](https://www.pgadmin.org) — the web UI for administering PostgreSQL. A `kurly.http` workload on the official image; its config store (SQLite) on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pgadmin = import 'github.com/metio/kurly/workloads/pgadmin/server.libsonnet';
kurly.list(pgadmin())
```

`PGADMIN_DEFAULT_EMAIL` and `PGADMIN_DEFAULT_PASSWORD` come from a Secret via `envFrom` — kurly authors **no Secret**. The image runs as uid 5050. Config at `/var/lib/pgadmin` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
