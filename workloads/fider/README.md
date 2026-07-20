<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# fider

[Fider](https://github.com/getfider/fider) — an open-source platform to collect and
prioritize customer feedback. A plain composable `kurly.http` workload on the official
image, backed by an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local fider = import 'github.com/metio/kurly/workloads/fider/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='fider-db', database='fider')).items,
  kurly.list(fider(baseUrl='https://feedback.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `fider` | |
| `image` | `docker.io/getfider/fider:v0.36.0` | |
| `baseUrl` | inferred | the public URL |
| `secretName` | `fider-secrets` | Secret with `DATABASE_URL`, `JWT_SECRET`, `EMAIL_*` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:3000` — compose an exposure onto it.

## Database and secrets

Fider reads `DATABASE_URL` (with the database password embedded), `JWT_SECRET`, and
its SMTP/email credentials from the environment. kurly authors **no Secret** — provide
`fider-secrets` holding them, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `fider-db`. Being stateless, it can run several
replicas.
