<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# changedetection

[changedetection.io](https://changedetection.io) — self-hosted website change detection:
watch pages and get notified when they change, with optional visual-diff and price
tracking. A plain composable `kurly.http` workload on the official image; its datastore
(SQLite plus page snapshots) lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local changedetection = import 'github.com/metio/kurly/workloads/changedetection/server.libsonnet';
kurly.list(changedetection(baseUrl='https://watch.example.com'))
```

Fetching JavaScript pages needs a companion Playwright/Chrome service
(`PLAYWRIGHT_DRIVER_URL`); the plain HTTP fetcher works without it. Datastore at
`/datastore` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:5000`.
