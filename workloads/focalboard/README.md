<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# focalboard

[Focalboard](https://github.com/mattermost/focalboard) — a self-hosted project-management
and kanban tool for boards, tasks and roadmaps, an open alternative to Trello/Notion/Asana.
A plain composable `kurly.http` workload on the official image; with the default SQLite
backend its database and uploaded files live on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local focalboard = import 'github.com/metio/kurly/workloads/focalboard/server.libsonnet';
kurly.list(focalboard())
```

Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8000`.
