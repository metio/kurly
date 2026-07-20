<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pocketbase

[PocketBase](https://pocketbase.io) — a self-hosted, open-source backend in one file: an embedded SQLite database, auth, file storage and a REST/realtime API, with an admin dashboard. A `kurly.http` workload; database, uploads and migrations on a PersistentVolume under `/pb_data`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pocketbase = import 'github.com/metio/kurly/workloads/pocketbase/server.libsonnet';
kurly.list(pocketbase())
```

Data at `/pb_data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the API and admin UI on `:8080`. On first run, create the superuser via the admin UI or the CLI.
