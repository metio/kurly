<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# greenlight

[Greenlight 3](https://github.com/bigbluebutton/greenlight) — the official
[BigBlueButton](https://bigbluebutton.org/) front-end: a Rails app for scheduling and
joining BBB rooms and meetings. A plain composable `kurly.http` workload on the
official image, backed by an external PostgreSQL and Redis. It reaches an existing
BigBlueButton server over the network — kurly does not run BBB itself.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local greenlight = import 'github.com/metio/kurly/workloads/greenlight/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='greenlight-db', database='greenlight')).items,
  kurly.list(greenlight()).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `greenlight` | |
| `image` | `docker.io/bigbluebutton/greenlight:v3.8.2.3` | |
| `replicas` | `2` | stateless — scale freely |
| `secretName` | `greenlight-secrets` | `DATABASE_URL`, `REDIS_URL`, `SECRET_KEY_BASE`, `BIGBLUEBUTTON_ENDPOINT`, `BIGBLUEBUTTON_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:3000` — compose an exposure onto it.

## Backends and secrets

Greenlight reads `DATABASE_URL`, `REDIS_URL`, `SECRET_KEY_BASE` and the BigBlueButton
endpoint/secret (`BIGBLUEBUTTON_ENDPOINT`, `BIGBLUEBUTTON_SECRET`) from the
environment. kurly authors **no Secret** — provide `greenlight-secrets` holding them,
pulled in via `envFrom` (fill it with [`kurly.externalSecret`](../../main.libsonnet)).
The defaults pair with a [cnpg-cluster](../cnpg-cluster/) named `greenlight-db` and a
Redis.

## Persistence

Recordings and presentations live on the BigBlueButton server, not here, so this is
**stateless** — a plain rolling Deployment with no volume.
