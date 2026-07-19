<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# actualbudget

[Actual Budget](https://github.com/actualbudget/actual) — a local-first personal
finance and budgeting app. A plain composable `kurly.http` workload that keeps its
budgets and sync state in a SQLite database on a PersistentVolume, so it needs no
external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local actual = import 'github.com/metio/kurly/workloads/actualbudget/server.libsonnet';

kurly.list(actual())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `actualbudget` | |
| `image` | `docker.io/actualbudget/actual-server:26.7.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the SQLite data volume (`/data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web app and sync API on `:5006` — compose an exposure onto it:

```jsonnet
kurly.listOf([
  actual()
  + kurly.expose.ownGateway('budget.example.com', 'istio', tls='actual-tls'),
  kurly.certificate('actual-tls', ['budget.example.com'], 'letsencrypt-prod'),
])
```

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica, recreated**
(never rolled) to keep two pods off the file — the same single-writer discipline as
[vaultwarden](../vaultwarden/).
