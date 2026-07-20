<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# calibre-web

[Calibre-Web](https://github.com/janeczku/calibre-web) — a clean web interface for
browsing, reading and downloading books from an existing Calibre library. A plain
composable `kurly.http` workload on the LinuxServer.io image; its config (SQLite) lives
on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local calibreWeb = import 'github.com/metio/kurly/workloads/calibre-web/server.libsonnet';
kurly.list(calibreWeb())
```

The LinuxServer.io s6-overlay init runs as root and drops to `puid`/`pgid`, so this runs
as root with a writable root filesystem (kurly keeps the rest of the hardening). Point
Calibre-Web at an existing library (the directory with `metadata.db`) on first run.
Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on
`:8083`.
