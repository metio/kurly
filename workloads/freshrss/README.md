<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# freshrss

[FreshRSS](https://github.com/FreshRSS/FreshRSS) — a free, self-hosted RSS and Atom
feed aggregator. A plain composable `kurly.http` workload on the official image: it
keeps its feeds and articles in a SQLite database on a PersistentVolume by default,
so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local freshrss = import 'github.com/metio/kurly/workloads/freshrss/server.libsonnet';

kurly.list(freshrss(baseUrl='https://rss.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `freshrss` | |
| `image` | `docker.io/freshrss/freshrss:1.29.1` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the SQLite data volume (`/var/www/FreshRSS/data`) |
| `baseUrl` | inferred | the public URL FreshRSS trusts |
| `env` | `{}` | extra environment (`CRON_MIN`, `TZ`, …) |
| `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:80` — compose an exposure onto it. Point it at an
external PostgreSQL/MySQL through the setup wizard to scale past the single SQLite
writer.

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. The SQLite database lives on a ReadWriteOnce volume, so this
is **one replica, recreated**.
