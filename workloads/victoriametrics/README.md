<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# victoriametrics

[VictoriaMetrics](https://victoriametrics.com) — a fast, cost-effective, self-hosted time-series database and Prometheus-compatible monitoring backend. A `kurly.http` workload on the official single-node image; data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local victoriametrics = import 'github.com/metio/kurly/workloads/victoriametrics/server.libsonnet';
kurly.list(victoriametrics())
```

`retentionPeriod` is in months (e.g. `'12'`). Data at `/victoria-metrics-data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8428`.
