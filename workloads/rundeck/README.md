<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# rundeck

[Rundeck](https://www.rundeck.com) — a self-hosted runbook-automation and operations platform: define jobs and workflows and run them across your nodes with access control and scheduling. A `kurly.http` workload on the official image; data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local rundeck = import 'github.com/metio/kurly/workloads/rundeck/server.libsonnet';
kurly.list(rundeck(grailsUrl='https://rundeck.example.com'))
```

The admin credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Point it at an external MySQL/PostgreSQL (`RUNDECK_DATABASE_*`) to scale past the embedded database. Data at `/home/rundeck/server/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:4440`.
