<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# clickhouse

[ClickHouse](https://clickhouse.com) — a fast, self-hosted column-oriented SQL database for real-time analytics. A `kurly.http` workload on the official single-node image; data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local clickhouse = import 'github.com/metio/kurly/workloads/clickhouse/server.libsonnet';
kurly.list(clickhouse())
```

`CLICKHOUSE_USER` / `CLICKHOUSE_PASSWORD` / `CLICKHOUSE_DB` come from a Secret via `envFrom` — kurly authors **no Secret**. The native protocol (`:9000`) needs an extra Service. Data at `/var/lib/clickhouse` on a ReadWriteOnce volume, so **one replica, recreated**. Serves HTTP on `:8123`.
