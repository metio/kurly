<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# grocy

A Grocy server — a self-hosted groceries and household management tool: stock, shopping lists, chores and recipes. A plain composable `kurly.http` workload on the LinuxServer.io image;
its config (SQLite) lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local grocy = import 'github.com/metio/kurly/workloads/grocy/server.libsonnet';
kurly.list(grocy())
```

The LinuxServer.io s6-overlay init runs as root and drops to `puid`/`pgid`, so this runs
as root with a writable root filesystem (kurly keeps the rest of the hardening). Config
at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
