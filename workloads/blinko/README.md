<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# blinko

[Blinko](https://github.com/blinko-space/blinko) — a self-hosted, AI-powered
note-taking app for quickly capturing ideas. A plain composable `kurly.http` workload
on the official image, backed by an external PostgreSQL, with its uploads on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local blinko = import 'github.com/metio/kurly/workloads/blinko/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='blinko-db', database='blinko')).items,
  kurly.list(blinko(nextauthUrl='https://notes.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `blinko` | |
| `image` | `docker.io/blinkospace/blinko:1.8.8` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | uploads (`/app/.blinko`) |
| `nextauthUrl` | inferred | the public URL |
| `secretName` | `blinko-secrets` | Secret with `DATABASE_URL` and `NEXTAUTH_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:1111` — compose an exposure onto it.

## Database and secrets

Blinko reads `DATABASE_URL` (with the database password embedded) and `NEXTAUTH_SECRET`
from the environment. kurly authors **no Secret** — provide `blinko-secrets` holding
both, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `blinko-db`.

## Persistence

Uploaded files live on a ReadWriteOnce volume, so this is **one replica, recreated**.
