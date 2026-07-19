<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# paisa

[Paisa](https://paisa.fyi/) — a plain-text, double-entry personal finance manager
built on ledger/beancount journals. A plain composable `kurly.http` workload that
reads its configuration and journal from a PersistentVolume, so it needs no
external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local paisa = import 'github.com/metio/kurly/workloads/paisa/server.libsonnet';

kurly.list(paisa())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `paisa` | |
| `image` | `ghcr.io/ananthakumaran/paisa:0.7.4` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the data volume (`/data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web UI on `:7500` — compose an exposure onto it:

```jsonnet
kurly.listOf([
  paisa()
  + kurly.expose.ownGateway('finance.example.com', 'istio', tls='paisa-tls'),
  kurly.certificate('paisa-tls', ['finance.example.com'], 'letsencrypt-prod'),
])
```

## Data

Paisa runs from `/data` and reads `paisa.yaml` and the journal it references from
there. Provide them on the volume before first use. The journal and its generated
database live on a ReadWriteOnce volume, so this is **one replica, recreated**.
