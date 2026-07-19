<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# overleaf

[Overleaf](https://github.com/overleaf/overleaf) — the Community Edition of the
collaborative LaTeX editor (formerly ShareLaTeX). A plain composable `kurly.http`
workload on the official monolith image, backed by an external MongoDB and Redis,
with its user projects and compiles on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local overleaf = import 'github.com/metio/kurly/workloads/overleaf/server.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(valkey(name='overleaf-cache')).items,
  kurly.list(overleaf(siteUrl='https://latex.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `overleaf` | |
| `image` | `docker.io/sharelatex/sharelatex:6.2.1` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | projects and compiles (`/var/lib/overleaf`) |
| `redisHost` | `overleaf-cache` | the Redis/valkey Service |
| `siteUrl` | inferred | the public URL |
| `appName` | `Overleaf` | the instance name |
| `secretName` | `overleaf-secrets` | Secret with `OVERLEAF_MONGO_URL` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Databases and secrets

Overleaf needs **MongoDB** (a **replica set** — it uses transactions) and **Redis**.
kurly ships no MongoDB recipe — bring your own; Redis can be the
[valkey](../valkey/) workload. It reads `OVERLEAF_REDIS_HOST` and its site config
from env, and `OVERLEAF_MONGO_URL` (with any credentials) from a provided Secret via
`envFrom`. kurly authors **no Secret** — fill `overleaf-secrets` with
[`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The image spawns TeX compile processes and writes across the root filesystem, so
this workload relaxes kurly's non-root and read-only-rootfs defaults while keeping
dropped capabilities and no privilege escalation. User projects and compiles live on
a ReadWriteOnce volume, so this is **one replica, recreated**.
