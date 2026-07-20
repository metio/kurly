<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# lidarr

Lidarr — a music collection manager for Usenet and BitTorrent users. A plain composable `kurly.http` workload on the LinuxServer.io image;
its application config (SQLite) lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local lidarr = import 'github.com/metio/kurly/workloads/lidarr/server.libsonnet';
kurly.list(lidarr())
```

The LinuxServer.io s6-overlay init runs as root and drops to `puid`/`pgid`, so this runs
as root with a writable root filesystem (kurly keeps the rest of the hardening). Mount
your media/download directories and point Lidarr at them in its settings. Config at
`/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8686`.
