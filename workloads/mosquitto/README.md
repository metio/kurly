<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mosquitto

[Eclipse Mosquitto](https://mosquitto.org) — a lightweight, self-hosted MQTT message broker, the backbone of most IoT and home-automation setups. Mosquitto speaks MQTT, not HTTP: it listens on `:1883`, with a `mosquitto.conf` mounted as a ConfigMap and its persistence database on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mosquitto = import 'github.com/metio/kurly/workloads/mosquitto/server.libsonnet';
kurly.list(mosquitto())
```

`config` is Mosquitto's `mosquitto.conf`, mounted verbatim; the default allows anonymous clients — a real broker sets up authentication. WebSockets (`:9001`) need a listener in the config and a second Service. Data at `/mosquitto/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves MQTT on `:1883`.
