<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wordpress

[WordPress](https://wordpress.org/) — the world's most popular CMS and blogging
platform. A plain composable `kurly.http` workload on the official image, backed by
an external MySQL/MariaDB, with its content (themes, plugins, uploads) on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wordpress = import 'github.com/metio/kurly/workloads/wordpress/server.libsonnet';

kurly.list(wordpress())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wordpress` | |
| `image` | `docker.io/library/wordpress:6.9.4-php8.3-apache` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | content (`/var/www/html`) |
| `dbHost` / `dbName` / `dbUser` | `wordpress-db` / `wordpress` / `wordpress` | the MySQL/MariaDB database |
| `secretName` | `wordpress-secrets` | Secret with `WORDPRESS_DB_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the site on `:80` — compose an exposure onto it.

## Database and secrets

WordPress needs a **MySQL/MariaDB** database. kurly ships no MySQL recipe — bring your
own and point `dbHost` at it. It reads `WORDPRESS_DB_HOST`, `WORDPRESS_DB_NAME`,
`WORDPRESS_DB_USER` from env and `WORDPRESS_DB_PASSWORD` from a provided Secret via
`envFrom`. kurly authors **no Secret** — fill `wordpress-secrets` with
[`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. The content lives on a ReadWriteOnce volume, so this is **one
replica, recreated**.
