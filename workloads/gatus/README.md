<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gatus

[Gatus](https://github.com/TwiN/gatus) — a self-hosted, developer-oriented health
dashboard and status page: it probes your endpoints on a schedule, evaluates conditions
and alerts. A plain composable `kurly.http` workload on the official image; its
configuration is mounted as a ConfigMap and its history database lives on a
PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gatus = import 'github.com/metio/kurly/workloads/gatus/server.libsonnet';

kurly.list(gatus(config={
  storage: { type: 'sqlite', path: '/data/gatus.db' },
  endpoints: [
    { name: 'api', url: 'https://api.example.com/health', interval: '1m',
      conditions: ['[STATUS] == 200', '[RESPONSE_TIME] < 300'] },
  ],
}))
```

`config` is Gatus's own schema (endpoints, conditions, alerting, storage, ui), rendered to
the mounted `config.yaml` verbatim — kurly does not model it. The default watches one
sample endpoint and persists history to SQLite on the data volume; replace it with your
own. History at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on
`:8080`.
