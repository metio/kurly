<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# readarr

[Readarr](https://readarr.com) — an ebook and audiobook collection manager for Usenet and BitTorrent users. A `kurly.http` workload on the LinuxServer.io image; application config (SQLite) on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local readarr = import 'github.com/metio/kurly/workloads/readarr/server.libsonnet';
kurly.list(readarr())
```

Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the web app and API on `:8787`. Mount your library and download directories and point Readarr at them in its settings.
