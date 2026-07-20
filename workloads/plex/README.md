<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# plex

[Plex Media Server](https://www.plex.tv) — a self-hosted media server for organising and streaming your movies, shows, music and photos. A `kurly.http` workload on the LinuxServer.io image; config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local plex = import 'github.com/metio/kurly/workloads/plex/server.libsonnet';
kurly.list(plex())
```

Runs as root (s6-overlay), dropping to `puid`/`pgid`. Set `PLEX_CLAIM` (from plex.tv/claim) on first run and mount your media libraries. Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:32400`.
