<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# nats

[NATS](https://nats.io) — a fast, lightweight, self-hosted messaging system for cloud-native apps: pub/sub, request/reply and, with JetStream, persistent streams. NATS speaks its own protocol on `:4222`, with its JetStream store on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local nats = import 'github.com/metio/kurly/workloads/nats/server.libsonnet';
kurly.list(nats())
```

JetStream is enabled with its store on the volume. Single server (a real deployment runs a NATS cluster). The monitoring endpoint (`:8222`) needs an extra Service. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves clients on `:4222`.
