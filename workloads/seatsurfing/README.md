<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# seatsurfing

[Seatsurfing](https://github.com/seatsurfing/seatsurfing) — desk and meeting-room
booking / hot-desking. A plain composable `kurly.http` workload on the official
image, backed by an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local seatsurfing = import 'github.com/metio/kurly/workloads/seatsurfing/server.libsonnet';

kurly.list(seatsurfing(env={ PUBLIC_URL: 'https://booking.example.com' }))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `seatsurfing` | |
| `image` | `ghcr.io/seatsurfing/seatsurfing:1.116.0` | |
| `secretName` | `seatsurfing-secrets` | Secret with `POSTGRES_URL` and `JWT_SIGNING_KEY` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` | `{}` | non-sensitive settings (`PUBLIC_URL`, `FRONTEND_URL`) |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:8080` — compose an exposure onto it.

## Database and secrets

Seatsurfing reads `POSTGRES_URL` and `JWT_SIGNING_KEY` from the environment. kurly
authors **no Secret** — provide `seatsurfing-secrets` holding both (the database
password is embedded in `POSTGRES_URL`), pulled in via `envFrom`. Fill it with
[`kurly.externalSecret`](../../main.libsonnet). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `seatsurfing-db`. Being stateless, it can run
several replicas.
