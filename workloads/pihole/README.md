<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pihole

[Pi-hole](https://pi-hole.net) — a self-hosted, network-wide DNS sinkhole that blocks ads and trackers, with a web admin dashboard. A `kurly.http` workload on the official image; config and query database on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pihole = import 'github.com/metio/kurly/workloads/pihole/server.libsonnet';
kurly.list(pihole())
```

Pi-hole answers **DNS on `:53`** (TCP/UDP) — add a Service for it (usually a LoadBalancer). The admin password (`FTLCONF_webserver_api_password`) comes from a Secret via `envFrom` — kurly authors **no Secret**. Config at `/etc/pihole` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the admin dashboard on `:80`.
