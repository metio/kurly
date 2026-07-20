<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# openobserve

[OpenObserve](https://openobserve.ai) — a self-hosted, high-performance observability platform for logs, metrics and traces. A `kurly.http` workload on the official image; data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local openobserve = import 'github.com/metio/kurly/workloads/openobserve/server.libsonnet';
kurly.list(openobserve())
```

`ZO_ROOT_USER_EMAIL` and `ZO_ROOT_USER_PASSWORD` come from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:5080`.
