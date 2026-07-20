<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# foldingathome

a Folding@home client — the distributed-computing client for disease research, with its web control panel. A `kurly.http` workload on the LinuxServer.io image; config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local foldingathome = import 'github.com/metio/kurly/workloads/foldingathome/server.libsonnet';
kurly.list(foldingathome())
```

Runs as root (s6-overlay), dropping to `puid`/`pgid`. Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:7396`.
