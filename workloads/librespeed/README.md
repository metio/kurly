<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# librespeed

A LibreSpeed server — a lightweight, self-hosted network speed test you run in the browser. A plain composable `kurly.http` workload on the LinuxServer.io image;
its config (SQLite) lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local librespeed = import 'github.com/metio/kurly/workloads/librespeed/server.libsonnet';
kurly.list(librespeed())
```

The LinuxServer.io s6-overlay init runs as root and drops to `puid`/`pgid`, so this runs
as root with a writable root filesystem (kurly keeps the rest of the hardening). Config
at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
