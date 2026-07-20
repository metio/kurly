<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pilos

[PILOS](https://github.com/THM-Health/PILOS) — an open-source, Laravel-based front-end
for [BigBlueButton](https://bigbluebutton.org/), developed at TH Mittelhessen: room and
meeting management with LDAP/OIDC support. A plain composable `kurly.http` workload on
the official all-in-one image (nginx + php-fpm), backed by an external PostgreSQL and
Redis, with its uploaded assets on a PersistentVolume. It reaches an existing
BigBlueButton server over the network — kurly does not run BBB itself.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pilos = import 'github.com/metio/kurly/workloads/pilos/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='pilos-db', database='pilos')).items,
  kurly.list(pilos()).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `pilos` | |
| `image` | `docker.io/pilos/pilos:4.17.0` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | uploaded assets (`/var/www/html/storage/app`) |
| `secretName` | `pilos-secrets` | database/Redis/`APP_KEY`/BBB settings (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Backends and secrets

PILOS reads its database, Redis, `APP_KEY` and the BigBlueButton server list from the
environment. kurly authors **no Secret** — provide `pilos-secrets` holding them,
pulled in via `envFrom` (fill it with [`kurly.externalSecret`](../../main.libsonnet)).
The defaults pair with a [cnpg-cluster](../cnpg-cluster/) named `pilos-db` and a Redis.

## Persistence

Uploaded logos and files live on a ReadWriteOnce volume, so this is **one replica,
recreated**. The bundled nginx master needs root and a writable root filesystem.
