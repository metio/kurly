<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# onlyoffice

[ONLYOFFICE Document Server](https://www.onlyoffice.com) — a self-hosted online office suite for collaborative editing of documents, spreadsheets and presentations, embedded by Nextcloud, Seafile and others. A `kurly.http` workload on the official image; data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local onlyoffice = import 'github.com/metio/kurly/workloads/onlyoffice/server.libsonnet';
kurly.list(onlyoffice())
```

The app that embeds it points its ONLYOFFICE connector at this URL. `JWT_SECRET` comes from a Secret via `envFrom` — kurly authors **no Secret**. The image bundles its own PostgreSQL and RabbitMQ. Data at `/var/www/onlyoffice/Data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
