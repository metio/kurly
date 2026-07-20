<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# jellyseerr

A Jellyseerr server — a request-management and media-discovery companion for Jellyfin, Emby and Plex, a fork of Overseerr. A plain composable `kurly.http` workload on the official image; its SQLite
configuration and database live on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local jellyseerr = import 'github.com/metio/kurly/workloads/jellyseerr/server.libsonnet';
kurly.list(jellyseerr())
```

Config at `/app/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves
on `:5055`.
