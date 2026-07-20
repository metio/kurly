<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# netbootxyz

a netboot.xyz server — a self-hosted network-boot menu and asset server for PXE-booting installers and tools. A plain composable `kurly.http` workload on the LinuxServer.io image; its
config lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local netbootxyz = import 'github.com/metio/kurly/workloads/netbootxyz/server.libsonnet';
kurly.list(netbootxyz())
```

The LinuxServer.io s6-overlay init runs as root and drops to `puid`/`pgid`, so this runs
as root with a writable root filesystem (kurly keeps the rest of the hardening). Config at
`/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:3000`.
