<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# piwigo

A Piwigo server — a self-hosted photo gallery with albums, tagging and user management (backed by MySQL/MariaDB). A plain composable `kurly.http` workload on the LinuxServer.io image; its
config (SQLite) lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local piwigo = import 'github.com/metio/kurly/workloads/piwigo/server.libsonnet';
kurly.list(piwigo())
```

The LinuxServer.io s6-overlay init runs as root and drops to `puid`/`pgid`, so this runs
as root with a writable root filesystem (kurly keeps the rest of the hardening). Config at
`/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
