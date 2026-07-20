<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# matrix-conduit

[Conduit](https://conduit.rs) — a lightweight, self-hosted Matrix homeserver written in Rust. A `kurly.http` workload on the official image; its embedded database on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local conduit = import 'github.com/metio/kurly/workloads/matrix-conduit/server.libsonnet';
kurly.list(conduit(serverName='matrix.example.com'))
```

The `serverName` is **baked into every user and room id at first start and cannot be changed** — set it deliberately, and make it reachable per the Matrix well-known/SRV rules. Data at `/var/lib/matrix-conduit` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:6167`.
