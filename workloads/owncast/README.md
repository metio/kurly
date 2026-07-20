<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# owncast

[Owncast](https://owncast.online) — a self-hosted live video streaming and chat server,
an open alternative to Twitch: you stream to it over RTMP and viewers watch on your own
site. A plain composable `kurly.http` workload on the official image; its data (SQLite
config, chat history, stream segments) lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local owncast = import 'github.com/metio/kurly/workloads/owncast/server.libsonnet';
kurly.list(owncast())
```

Streaming **into** Owncast uses RTMP on `:1935`, a separate port this HTTP workload does
not expose — add a Service for it (a raw `+` patch or a dedicated LoadBalancer). The web
player works without it. Data at `/app/data` on a ReadWriteOnce volume, so **one replica,
recreated**. Serves the web player on `:8080`.
