<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pairdrop

[PairDrop](https://github.com/schlagmichdoch/PairDrop) — a self-hosted, AirDrop-style
local file-sharing app: transfer files and messages between devices over the browser,
peer-to-peer via WebRTC. A plain composable `kurly.http` workload on the official image;
the server only brokers peer connections and keeps no state.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pairdrop = import 'github.com/metio/kurly/workloads/pairdrop/server.libsonnet';
kurly.list(pairdrop())
```

Runs as **one replica** — peers pair through in-memory rooms held by a single server
instance, so more than one replica without sticky routing would split rooms across pods.
Serves on `:3000`.
