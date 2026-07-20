<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# homepage

[Homepage](https://gethomepage.dev) — a modern, fully static, highly-configurable
application dashboard with service/bookmark widgets and live status. A plain composable
`kurly.http` workload on the official image; its YAML configuration lives on a
PersistentVolume, so it needs no external database.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local homepage = import 'github.com/metio/kurly/workloads/homepage/server.libsonnet';
kurly.list(homepage(allowedHosts='home.example.com'))
```

Set `allowedHosts` (`HOMEPAGE_ALLOWED_HOSTS`) to the host you serve it on — recent
releases reject other Host headers. Config lives at `/app/config` on a ReadWriteOnce
volume, so this is **one replica, recreated**. Serves on `:3000`.
