<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# bigcapital

[Bigcapital](https://github.com/bigcapitalhq/bigcapital) — self-hosted accounting
and financial management. Three composable `kurly.http` stages on the official
images: `server` (the API), `webapp` (the front end), and `gateway` (the nginx
entry you expose), backed by external MySQL/MariaDB, MongoDB, and Redis.

## Compose

All three stages must share the same `namePrefix` (default `bigcapital`) and
`secretName` — the gateway reaches the server and webapp by Service names derived
from `namePrefix`. Expose **only the gateway**.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local server = import 'github.com/metio/kurly/workloads/bigcapital/server.libsonnet';
local webapp = import 'github.com/metio/kurly/workloads/bigcapital/webapp.libsonnet';
local gateway = import 'github.com/metio/kurly/workloads/bigcapital/gateway.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(server(baseUrl='https://accounting.example.com')).items,
  kurly.list(webapp()).items,
  kurly.list(gateway()).items,
]))
```

| Stage | Port | Role |
|---|---|---|
| `gateway` | 80 | nginx entry — **expose this**; routes to webapp and `/api` to server |
| `server` | 4000 | the API; needs MySQL, MongoDB, and Redis |
| `webapp` | 80 | the single-page front end (stateless) |

## Databases and secrets

Bigcapital needs **MySQL/MariaDB** (system and per-tenant data), **MongoDB**, and
**Redis**. kurly ships no MySQL or MongoDB recipe — bring your own; Redis can be the
[valkey](../valkey/) workload. The server reads its host coordinates from env and
its passwords and `JWT_SECRET` from a provided Secret via `envFrom`. kurly authors
**no Secret** — fill `bigcapital-secrets` with
[`kurly.externalSecret`](../../main.libsonnet).

## Security

The webapp and gateway are nginx images that start as **root** and bind `:80`, so
those stages relax kurly's non-root and read-only-rootfs defaults while keeping
dropped capabilities and no privilege escalation. The server runs non-root under the
restricted posture.

> Bigcapital's exact environment-variable names evolve across releases — verify the
> `server` env against the version's compose file, and adjust through the `env`
> parameter as needed.
