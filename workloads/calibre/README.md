<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# calibre

a Calibre server — the full Calibre e-book management desktop app, served in the browser over a remote-desktop session. A plain composable `kurly.http` workload on the LinuxServer.io image; its
config lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local calibre = import 'github.com/metio/kurly/workloads/calibre/server.libsonnet';
kurly.list(calibre())
```

The LinuxServer.io s6-overlay init runs as root and drops to `puid`/`pgid`, so this runs
as root with a writable root filesystem (kurly keeps the rest of the hardening). Config at
`/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8080`.
