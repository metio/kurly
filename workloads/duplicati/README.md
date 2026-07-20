<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# duplicati

a Duplicati server — a self-hosted, encrypted backup client for cloud and remote storage, managed from the browser. A `kurly.http` workload on the LinuxServer.io image; config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local duplicati = import 'github.com/metio/kurly/workloads/duplicati/server.libsonnet';
kurly.list(duplicati())
```

Runs as root (s6-overlay), dropping to `puid`/`pgid`. Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8200`.
