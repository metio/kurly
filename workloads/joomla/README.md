<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# joomla

A Joomla server — a popular self-hosted CMS for building websites and online applications (backed by MySQL). A `kurly.http` workload on the official image, backed by an external database, with data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local joomla = import 'github.com/metio/kurly/workloads/joomla/server.libsonnet';
kurly.list(joomla())
```

The DB credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/var/www/html` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
