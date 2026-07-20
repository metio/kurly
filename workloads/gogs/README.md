<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gogs

[Gogs](https://gogs.io) — a painless, self-hosted Git service: a lightweight, fast Git
server with a clean web UI. A plain composable `kurly.http` workload on the official
image; with the default SQLite backend its repositories and data live on a
PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gogs = import 'github.com/metio/kurly/workloads/gogs/server.libsonnet';
kurly.list(gogs())
```

Git-over-SSH uses `:22` — add a Service for it; HTTP(S) Git works without it. Data at
`/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:3000`.
