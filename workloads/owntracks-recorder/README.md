<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# owntracks-recorder

[OwnTracks Recorder](https://github.com/owntracks/recorder) — a self-hosted store and web UI for the location data your OwnTracks phone apps publish. A `kurly.http` workload on the official image; the location store on a PersistentVolume under `/store`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local recorder = import 'github.com/metio/kurly/workloads/owntracks-recorder/server.libsonnet';
kurly.list(recorder())
```

Store at `/store` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the UI and HTTP recorder endpoint on `:8083`. The phone apps can publish over HTTP directly, or via an MQTT broker the Recorder subscribes to (`OTR_HOST`/`OTR_PORT`).
