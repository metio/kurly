<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# healthchecks

[Healthchecks](https://healthchecks.io) — a self-hosted cron-job and background-task
monitoring service: your jobs ping a URL when they finish, and it alerts you when a ping is
late or missing. A plain composable `kurly.http` workload on the official image; with the
default SQLite backend its database lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local healthchecks = import 'github.com/metio/kurly/workloads/healthchecks/server.libsonnet';
kurly.list(healthchecks(siteRoot='https://checks.example.com', allowedHosts='checks.example.com'))
```

Healthchecks needs `SECRET_KEY` from a Secret via `envFrom` — kurly authors **no Secret**.
Point it at an external PostgreSQL (`DB=postgres` plus the `DB_*` connection) to scale past
SQLite. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on
`:8000`.
