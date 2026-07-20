<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gitea

[Gitea](https://gitea.io) — a lightweight, self-hosted Git service with issues, pull
requests, a package registry and CI via Actions. A plain composable `kurly.http` workload
on the official image; with the default SQLite backend its repositories and data live on
a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gitea = import 'github.com/metio/kurly/workloads/gitea/server.libsonnet';
kurly.list(gitea(rootUrl='https://git.example.com'))
```

The official image uses s6-overlay, so it runs as root and drops to `uid`/`gid`.
Git-over-SSH uses `:22` — add a Service for it; HTTP(S) Git works without it. Point Gitea
at an external PostgreSQL/MySQL (`GITEA__database__*`) to scale past the single SQLite
writer. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves
on `:3000`.
