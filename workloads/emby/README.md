<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# emby

[Emby](https://emby.media) — a self-hosted media server for streaming your movies, shows, music and photos. A `kurly.http` workload on the LinuxServer.io image; config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local emby = import 'github.com/metio/kurly/workloads/emby/server.libsonnet';
kurly.list(emby())
```

Runs as root (s6-overlay), dropping to `puid`/`pgid`. Mount your media libraries and add them in the UI. Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8096`.
