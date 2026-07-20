<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# nzbhydra2

an NZBHydra2 server — a meta-search server that aggregates Usenet indexers behind one search API for the *arr apps. A `kurly.http` workload on the LinuxServer.io image; config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local nzbhydra2 = import 'github.com/metio/kurly/workloads/nzbhydra2/server.libsonnet';
kurly.list(nzbhydra2())
```

Runs as root (s6-overlay), dropping to `puid`/`pgid`. Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:5076`.
