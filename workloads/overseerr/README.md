<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# overseerr

An Overseerr server — a request-management and media-discovery companion for Plex, integrating with Sonarr and Radarr. A plain composable `kurly.http` workload on the official image; its SQLite
configuration and database live on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local overseerr = import 'github.com/metio/kurly/workloads/overseerr/server.libsonnet';
kurly.list(overseerr())
```

Config at `/app/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves
on `:5055`.
