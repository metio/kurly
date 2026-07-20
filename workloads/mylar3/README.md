<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mylar3

a Mylar3 server — a self-hosted comic-book (CBR/CBZ) downloader and library manager. A plain composable `kurly.http` workload on the LinuxServer.io image; its
config lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mylar3 = import 'github.com/metio/kurly/workloads/mylar3/server.libsonnet';
kurly.list(mylar3())
```

The LinuxServer.io s6-overlay init runs as root and drops to `puid`/`pgid`, so this runs
as root with a writable root filesystem (kurly keeps the rest of the hardening). Config at
`/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8090`.
