<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# rallly

[Rallly](https://github.com/lukevella/rallly) — a self-hosted scheduling and
group-poll tool for finding the best date to meet. A plain composable `kurly.http`
workload on the official image, backed by an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local rallly = import 'github.com/metio/kurly/workloads/rallly/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='rallly-db', database='rallly')).items,
  kurly.list(rallly(baseUrl='https://rallly.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `rallly` | |
| `image` | `ghcr.io/lukevella/rallly:4.11.1` | |
| `baseUrl` | inferred | the public URL |
| `secretName` | `rallly-secrets` | Secret with `DATABASE_URL`, `SECRET_PASSWORD`, `SMTP_*` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:3000` — compose an exposure onto it.

## Database and secrets

Rallly reads `DATABASE_URL` (with the database password embedded), `SECRET_PASSWORD`,
and its SMTP credentials from the environment. kurly authors **no Secret** — provide
`rallly-secrets` holding them, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `rallly-db`. Being stateless, it can run several
replicas.
