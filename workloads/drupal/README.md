<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# drupal

A Drupal server — a powerful, self-hosted open-source CMS and content framework (backed by MySQL/PostgreSQL). A `kurly.http` workload on the official image, backed by an external database, with data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local drupal = import 'github.com/metio/kurly/workloads/drupal/server.libsonnet';
kurly.list(drupal())
```

The DB credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/var/www/html/sites` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
