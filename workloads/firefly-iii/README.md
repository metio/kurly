<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# firefly-iii

[Firefly III](https://github.com/firefly-iii/firefly-iii) — a free, self-hosted
personal-finance manager. A plain composable `kurly.http` workload on the official
image, backed by an external PostgreSQL, with its uploads on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local firefly = import 'github.com/metio/kurly/workloads/firefly-iii/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='firefly-iii-db', database='firefly')).items,
  kurly.list(firefly(appUrl='https://finance.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `firefly-iii` | |
| `image` | `docker.io/fireflyiii/core:version-6.6.6` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | uploads |
| `dbHost` / `dbName` / `dbUser` | `firefly-iii-db-rw` / `firefly` / `firefly` | the PostgreSQL database |
| `appUrl` | inferred | the public URL |
| `secretName` | `firefly-iii-secrets` | Secret with `DB_PASSWORD` and `APP_KEY` (32-char, envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:8080` — compose an exposure onto it.

## Database and secrets

Firefly III reads its database coordinates from env and `DB_PASSWORD` and `APP_KEY`
from a provided Secret via `envFrom`. kurly authors **no Secret** — fill
`firefly-iii-secrets` with [`kurly.externalSecret`](../../main.libsonnet). The defaults
pair with a [cnpg-cluster](../cnpg-cluster/) named `firefly-iii-db`.

## Security and persistence

The Apache + PHP image starts as **root** and binds `:8080`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. Uploads live on a ReadWriteOnce volume, so this is **one
replica, recreated**.
