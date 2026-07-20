<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pingvin-share

[Pingvin Share](https://github.com/stonith404/pingvin-share) — a self-hosted, open-source file-sharing platform, an alternative to WeTransfer. A `kurly.http` workload on the official all-in-one image; SQLite database and uploaded shares on a PersistentVolume under `/opt/app/backend/data`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pingvin = import 'github.com/metio/kurly/workloads/pingvin-share/server.libsonnet';
kurly.list(pingvin())
```

Data at `/opt/app/backend/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:3000`.
