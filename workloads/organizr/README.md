<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# organizr

[Organizr](https://organizr.app) — a self-hosted HTPC/homelab services dashboard that ties your apps together behind one tabbed interface with authentication. A `kurly.http` workload on the official image (pinned by digest — Renovate maintains it); SQLite config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local organizr = import 'github.com/metio/kurly/workloads/organizr/server.libsonnet';
kurly.list(organizr())
```

Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
