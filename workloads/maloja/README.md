<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# maloja

[Maloja](https://github.com/krateng/maloja) — a self-hosted music scrobble database and listening-statistics server, a self-hosted alternative to Last.fm. A `kurly.http` workload on the official image; database (SQLite) and configuration on a PersistentVolume under `/mljdata`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local maloja = import 'github.com/metio/kurly/workloads/maloja/server.libsonnet';
kurly.list(maloja())
```

Data at `/mljdata` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:42010`.
