<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mongo

MongoDB server — a self-hosted, document-oriented NoSQL database. A `kurly.http` workload (for its Deployment/Service plumbing) on the official image; the server speaks its own protocol on `:27017`, with data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mongo = import 'github.com/metio/kurly/workloads/mongo/server.libsonnet';
kurly.list(mongo())
```

A **single instance** (not a replicated cluster — use the operator-backed cluster workloads for HA). Credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/data/db` on a ReadWriteOnce volume, so **one replica, recreated**. Reached in-cluster on `:27017`.
