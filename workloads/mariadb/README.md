<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mariadb

MariaDB server — a self-hosted relational database, the community-developed fork of MySQL. A `kurly.http` workload (for its Deployment/Service plumbing) on the official image; the server speaks its own protocol on `:3306`, with data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mariadb = import 'github.com/metio/kurly/workloads/mariadb/server.libsonnet';
kurly.list(mariadb())
```

A **single instance** (not a replicated cluster — use the operator-backed cluster workloads for HA). Credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/var/lib/mysql` on a ReadWriteOnce volume, so **one replica, recreated**. Reached in-cluster on `:3306`.
