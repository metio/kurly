<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# emqx

[EMQX](https://www.emqx.io) — a highly-scalable, self-hosted MQTT broker for IoT, with a web dashboard, rules engine and clustering. EMQX speaks MQTT on `:1883`, with data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local emqx = import 'github.com/metio/kurly/workloads/emqx/server.libsonnet';
kurly.list(emqx())
```

Single node (not a cluster). Expose `:1883` to devices (often a LoadBalancer); the dashboard (`:18083`) needs an extra Service. Data at `/opt/emqx/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves MQTT on `:1883`.
