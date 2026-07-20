<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# nzbget

an NZBGet server — an efficient, self-hosted Usenet downloader written in C++. A plain composable `kurly.http` workload on the LinuxServer.io image; its
config (SQLite) lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local nzbget = import 'github.com/metio/kurly/workloads/nzbget/server.libsonnet';
kurly.list(nzbget())
```

The LinuxServer.io s6-overlay init runs as root and drops to `puid`/`pgid`, so this runs
as root with a writable root filesystem (kurly keeps the rest of the hardening). Config at
`/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:6789`.
