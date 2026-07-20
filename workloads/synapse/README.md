<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# synapse

[Synapse](https://github.com/element-hq/synapse) — the reference Matrix homeserver from the Matrix.org Foundation. A `kurly.http` workload on the official image; config, signing keys and (with the default SQLite backend) database on a PersistentVolume, generated on first start.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local synapse = import 'github.com/metio/kurly/workloads/synapse/server.libsonnet';
kurly.list(synapse(serverName='matrix.example.com'))
```

The `serverName` is **baked into every id and cannot be changed** — set it deliberately. Beyond a small instance, edit the generated `homeserver.yaml` on the volume to point at an external PostgreSQL. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8008`.
