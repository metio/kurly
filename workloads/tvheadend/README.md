<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# tvheadend

[Tvheadend](https://tvheadend.org) — a self-hosted TV streaming server and DVR (DVB, IPTV, SAT>IP) with a web UI. A `kurly.http` workload on the LinuxServer.io image (pinned by digest — Renovate maintains it); config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local tvheadend = import 'github.com/metio/kurly/workloads/tvheadend/server.libsonnet';
kurly.list(tvheadend())
```

Runs as root (s6-overlay), dropping to `puid`/`pgid`. HTSP streaming (`:9982`) needs an extra Service; tuners are hardware and not modelled here. Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the web UI on `:9981`.
