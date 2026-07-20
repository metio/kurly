<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# airsonic-advanced

an Airsonic-Advanced server — a free, self-hosted music streaming server, an actively-maintained fork of Airsonic. A plain composable `kurly.http` workload on the LinuxServer.io image; its
config lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local airsonic-advanced = import 'github.com/metio/kurly/workloads/airsonic-advanced/server.libsonnet';
kurly.list(airsonic-advanced())
```

The LinuxServer.io s6-overlay init runs as root and drops to `puid`/`pgid`, so this runs
as root with a writable root filesystem (kurly keeps the rest of the hardening). Config at
`/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:4040`.
