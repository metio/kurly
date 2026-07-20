<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# thelounge

[The Lounge](https://github.com/thelounge/thelounge) — a modern, self-hosted web IRC client: always-connected, multi-user, accessible from any browser. A `kurly.http` workload on the official image; config and per-user data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local thelounge = import 'github.com/metio/kurly/workloads/thelounge/server.libsonnet';
kurly.list(thelounge())
```

Data at `/var/opt/thelounge` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:9000`.
