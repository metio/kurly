<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ombi

An Ombi server — a request-management portal for Plex, Emby and Jellyfin, letting users ask for new media. A plain composable `kurly.http` workload on the LinuxServer.io image; its
config (SQLite) lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ombi = import 'github.com/metio/kurly/workloads/ombi/server.libsonnet';
kurly.list(ombi())
```

The LinuxServer.io s6-overlay init runs as root and drops to `puid`/`pgid`, so this runs
as root with a writable root filesystem (kurly keeps the rest of the hardening). Config
at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:3579`.
