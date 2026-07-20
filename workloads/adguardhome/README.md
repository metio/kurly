<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# adguardhome

[AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) — a self-hosted, network-wide
DNS ad- and tracker-blocker with a friendly web UI, an alternative to Pi-hole. A plain
composable `kurly.http` workload on the official image; its configuration and runtime data
live on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local adguardhome = import 'github.com/metio/kurly/workloads/adguardhome/server.libsonnet';
kurly.list(adguardhome())
```

AdGuard Home answers **DNS on `:53`** (TCP and UDP), separate ports this HTTP workload does
not expose — add a Service for `:53` (usually a LoadBalancer) so clients can point their
resolver at it. The config and work directory both live under `/opt/adguardhome`, so a
single volume persists everything; on a ReadWriteOnce volume this is **one replica,
recreated**. The admin UI (first-run setup wizard) serves on `:3000`.
