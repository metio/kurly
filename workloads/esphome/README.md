<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# esphome

[ESPHome](https://esphome.io) — the web dashboard and compiler for creating and flashing firmware for ESP8266/ESP32 smart-home devices from YAML. A `kurly.http` workload on the official image; device configs and build artifacts on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local esphome = import 'github.com/metio/kurly/workloads/esphome/server.libsonnet';
kurly.list(esphome())
```

Runs as root to compile firmware; OTA flashing works over the network. Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:6052`.
