<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# davos

a davos server — a self-hosted FTP automation tool that watches remote directories and downloads on a schedule. A `kurly.http` workload on the LinuxServer.io image; config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local davos = import 'github.com/metio/kurly/workloads/davos/server.libsonnet';
kurly.list(davos())
```

Runs as root (s6-overlay), dropping to `puid`/`pgid`. Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8080`.
