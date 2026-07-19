<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# passwordpusher

[Password Pusher](https://github.com/pglombardo/PasswordPusher) — share passwords
and secrets over self-destructing, expiring links. A plain composable `kurly.http`
workload on the official image, backed by an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pwpush = import 'github.com/metio/kurly/workloads/passwordpusher/server.libsonnet';

kurly.list(pwpush())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `passwordpusher` | |
| `image` | `docker.io/pglombardo/pwpush:v2.9.3` | |
| `secretName` | `passwordpusher-secrets` | Secret with `DATABASE_URL` and `SECRET_KEY_BASE` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:5100` — compose an exposure onto it:

```jsonnet
kurly.listOf([
  pwpush()
  + kurly.expose.ownGateway('pw.example.com', 'istio', tls='pwpush-tls'),
  kurly.certificate('pwpush-tls', ['pw.example.com'], 'letsencrypt-prod'),
])
```

## Database and secrets

Password Pusher reads `DATABASE_URL` and `SECRET_KEY_BASE` from the environment.
kurly authors **no Secret** — provide `passwordpusher-secrets` holding both keys
(the database password is embedded in `DATABASE_URL`), pulled in via `envFrom`. Fill
it with [`kurly.externalSecret`](../../main.libsonnet). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `passwordpusher-db`. Being stateless (state
in the database), it can run several replicas.
