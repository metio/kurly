<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# node-red

[Node-RED](https://nodered.org) — a flow-based, low-code programming tool for wiring together APIs, devices and online services. A `kurly.http` workload on the official image; flows and settings on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local nodeRed = import 'github.com/metio/kurly/workloads/node-red/server.libsonnet';
kurly.list(nodeRed())
```

Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:1880`.
