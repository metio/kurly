<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wallabag

[wallabag](https://github.com/wallabag/wallabag) — a self-hosted read-it-later app
that saves clean, readable copies of web pages. A plain composable `kurly.http`
workload on the official image, backed by an external PostgreSQL, with its saved
images on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wallabag = import 'github.com/metio/kurly/workloads/wallabag/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='wallabag-db', database='wallabag')).items,
  kurly.list(wallabag(domain='https://read.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wallabag` | |
| `image` | `docker.io/wallabag/wallabag:2.6.14` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | saved images |
| `dbHost` / `dbName` / `dbUser` | `wallabag-db-rw` / `wallabag` / `wallabag` | the PostgreSQL database |
| `domain` | inferred | the public URL |
| `secretName` | `wallabag-secrets` | Secret with `SYMFONY__ENV__DATABASE_PASSWORD` and `SYMFONY__ENV__SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:80` — compose an exposure onto it.

## Database and secrets

wallabag reads its database coordinates from env (with the `SYMFONY__ENV__` prefix)
and the database password and app secret from a provided Secret via `envFrom`. kurly
authors **no Secret** — fill `wallabag-secrets` with
[`kurly.externalSecret`](../../main.libsonnet). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `wallabag-db`.

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. Saved images live on a ReadWriteOnce volume, so this is **one
replica, recreated**.
