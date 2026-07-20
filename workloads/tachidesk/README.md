<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# tachidesk

[Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server) (formerly Tachidesk) — a self-hosted manga reader and library server. A `kurly.http` workload on the official image; library and settings on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local tachidesk = import 'github.com/metio/kurly/workloads/tachidesk/server.libsonnet';
kurly.list(tachidesk())
```

Data on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:4567`.
