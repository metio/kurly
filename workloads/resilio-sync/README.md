<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# resilio-sync

a Resilio Sync server — a fast, peer-to-peer file-synchronization tool (BitTorrent-based) with a web UI. A `kurly.http` workload on the LinuxServer.io image; config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local resilio-sync = import 'github.com/metio/kurly/workloads/resilio-sync/server.libsonnet';
kurly.list(resilio-sync())
```

Runs as root (s6-overlay), dropping to `puid`/`pgid`. Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8888`.
