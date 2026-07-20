<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# redis

Redis server — an in-memory data store used as a cache, message broker and database. A `kurly.http` workload (for its Deployment/Service plumbing) on the official image; the server speaks its own protocol on `:6379`, with data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local redis = import 'github.com/metio/kurly/workloads/redis/server.libsonnet';
kurly.list(redis())
```

A **single instance** (not a replicated cluster — use the operator-backed cluster workloads for HA). Credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Reached in-cluster on `:6379`.
