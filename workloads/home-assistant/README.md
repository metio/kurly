<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# home-assistant

[Home Assistant](https://www.home-assistant.io) (Core) — the leading self-hosted home-automation platform, integrating thousands of smart-home devices behind one dashboard and automation engine. A `kurly.http` workload on the official image; config and state database on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local homeAssistant = import 'github.com/metio/kurly/workloads/home-assistant/server.libsonnet';
kurly.list(homeAssistant())
```

Runs as root with a writable `/config`. Local-network discovery (mDNS/SSDP) does not work through a ClusterIP; devices reachable by IP/MQTT/cloud work normally, and USB radios need a network coordinator. Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8123`.
