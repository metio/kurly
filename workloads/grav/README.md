<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# grav

[Grav](https://getgrav.org) — a modern, flat-file CMS: fast, database-free content
management with a Markdown-driven admin. A plain composable `kurly.http` workload on the
LinuxServer.io image; because Grav is flat-file, its whole site lives on a
PersistentVolume — no external database.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local grav = import 'github.com/metio/kurly/workloads/grav/server.libsonnet';
kurly.list(grav())
```

The LinuxServer.io s6-overlay init runs as root and drops to `puid`/`pgid`, so this runs
as root with a writable root filesystem (kurly keeps the rest of the hardening). Site at
`/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
