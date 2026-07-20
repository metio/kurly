<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# traccar

[Traccar](https://www.traccar.org) — a self-hosted GPS tracking platform: it ingests
position reports from a huge range of GPS devices and phone apps and shows them live on a
map. A plain composable `kurly.http` workload on the official image; its server settings
are a `traccar.xml` mounted as a ConfigMap, and with the default embedded H2 database its
data lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local traccar = import 'github.com/metio/kurly/workloads/traccar/server.libsonnet';
kurly.list(traccar())
```

`configXml` is Traccar's `traccar.xml`, mounted verbatim; the default points the embedded
H2 database at the data volume — replace the `database.*` entries to use an external
PostgreSQL/MySQL. Traccar listens for device protocols on extra ports (5000-5150) — add
Services for the protocols your devices use. Data at `/opt/traccar/data` on a ReadWriteOnce
volume, so **one replica, recreated**. Serves on `:8082`.
