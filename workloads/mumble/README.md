<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mumble

[Mumble](https://www.mumble.info) (Murmur) — a self-hosted, low-latency voice-chat server for gaming and communities. Mumble speaks its own voice protocol, not HTTP: it listens on `:64738` (TCP control, UDP voice), with its SQLite database on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mumble = import 'github.com/metio/kurly/workloads/mumble/server.libsonnet';
kurly.list(mumble())
```

The Service publishes the **TCP** control port; add a second Service for **UDP** voice (usually a LoadBalancer) — expose it to clients rather than an HTTP ingress. `MUMBLE_SUPERUSER_PASSWORD` comes from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**.
