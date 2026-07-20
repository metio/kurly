<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# leantime

[Leantime](https://leantime.io) — a self-hosted, open-source project-management system for non-project-managers: goals, ideas, tasks, time tracking. A `kurly.http` workload on the official image, backed by an external MySQL/MariaDB; uploaded files on a PersistentVolume under `/var/www/html/userfiles`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local leantime = import 'github.com/metio/kurly/workloads/leantime/server.libsonnet';
kurly.list(leantime())
```

Uploads at `/var/www/html/userfiles` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8080`.

**Secrets:** Leantime reads `LEAN_DB_*` and `LEAN_SESSION_PASSWORD` from the environment. kurly authors no Secret; provide one (via `secretName`) holding them. Pair it with a MySQL/MariaDB you run separately.
