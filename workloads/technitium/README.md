<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# technitium

[Technitium DNS Server](https://technitium.com/dns/) — a self-hosted, privacy-focused DNS server with ad-blocking, DNS-over-HTTPS/TLS and a full web console. A `kurly.http` workload on the official image; config and zones on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local technitium = import 'github.com/metio/kurly/workloads/technitium/server.libsonnet';
kurly.list(technitium())
```

Answers **DNS on `:53`** (TCP/UDP) — add a Service for it (usually a LoadBalancer). The admin password (`DNS_SERVER_ADMIN_PASSWORD`) comes from a Secret via `envFrom` — kurly authors **no Secret**. Config at `/etc/dns` on a ReadWriteOnce volume, so **one replica, recreated**. The web console serves on `:5380`.
