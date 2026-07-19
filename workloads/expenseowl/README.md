<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# expenseowl

[ExpenseOwl](https://github.com/tanq16/expenseowl) — a simple, self-hosted expense
tracker. A plain composable `kurly.http` workload that keeps its expenses in a
file-backed store on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local expenseowl = import 'github.com/metio/kurly/workloads/expenseowl/server.libsonnet';

kurly.list(expenseowl())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `expenseowl` | |
| `image` | `ghcr.io/tanq16/expenseowl:v4.1` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the data volume (`/app/data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:8080` — compose an exposure onto it:

```jsonnet
kurly.listOf([
  expenseowl()
  + kurly.expose.ownGateway('expenses.example.com', 'istio', tls='expenseowl-tls'),
  kurly.certificate('expenseowl-tls', ['expenses.example.com'], 'letsencrypt-prod'),
])
```

## Persistence

One file-backed store on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled) to keep two pods off the files — the same single-writer
discipline as [vaultwarden](../vaultwarden/).
