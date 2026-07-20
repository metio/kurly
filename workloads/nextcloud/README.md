<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# nextcloud

[Nextcloud](https://nextcloud.com) — a self-hosted content-collaboration platform: file sync and share, calendars, contacts, office documents and a large app ecosystem. A `kurly.http` workload on the official Apache image; with the default SQLite backend the whole installation on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local nextcloud = import 'github.com/metio/kurly/workloads/nextcloud/server.libsonnet';
kurly.list(nextcloud(trustedDomains='cloud.example.com'))
```

SQLite suits a small instance; point it at an external PostgreSQL/MySQL and S3 primary storage to scale out. `NEXTCLOUD_ADMIN_*` come from a Secret via `envFrom` — kurly authors **no Secret**. Installation at `/var/www/html` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
