<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mediawiki

[MediaWiki](https://www.mediawiki.org/) — the wiki engine behind Wikipedia. A plain
composable `kurly.http` workload on the official image, backed by an external
MySQL/MariaDB, with its uploaded files on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mediawiki = import 'github.com/metio/kurly/workloads/mediawiki/server.libsonnet';

kurly.list(mediawiki())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `mediawiki` | |
| `image` | `docker.io/library/mediawiki:1.45.4` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | uploaded files (`/var/www/html/images`) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the wiki on `:80` — compose an exposure onto it.

## Configuration

MediaWiki is configured by a `LocalSettings.php` (database credentials, secret keys,
extensions). Generate it once with the web installer, or author it, and mount it at
`/var/www/html/LocalSettings.php` from a Secret (it holds the database password and
`$wgSecretKey`) — kurly authors **none**. The database is a **MySQL/MariaDB** — the
[mysql-cluster](../mysql-cluster/) workload provides one.

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. Uploaded files live on a ReadWriteOnce volume, so this is
**one replica, recreated**.
