<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# influxdb

[InfluxDB 2](https://www.influxdata.com) — a self-hosted time-series database for metrics, events and IoT data, with a built-in UI and query engine. A `kurly.http` workload on the official image; data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local influxdb = import 'github.com/metio/kurly/workloads/influxdb/server.libsonnet';
kurly.list(influxdb())
```

The `DOCKER_INFLUXDB_INIT_*` setup values come from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/var/lib/influxdb2` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8086`.
