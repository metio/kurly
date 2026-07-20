<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# sabnzbd

a SABnzbd server — a self-hosted, web-based binary newsreader (Usenet downloader). A plain composable `kurly.http` workload on the LinuxServer.io image; its
config (SQLite) lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local sabnzbd = import 'github.com/metio/kurly/workloads/sabnzbd/server.libsonnet';
kurly.list(sabnzbd())
```

The LinuxServer.io s6-overlay init runs as root and drops to `puid`/`pgid`, so this runs
as root with a writable root filesystem (kurly keeps the rest of the hardening). Config at
`/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8080`.
