<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# prestashop

A PrestaShop server — a self-hosted, open-source e-commerce platform for building online stores (backed by MySQL). A `kurly.http` workload on the official image, backed by an external database, with data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local prestashop = import 'github.com/metio/kurly/workloads/prestashop/server.libsonnet';
kurly.list(prestashop())
```

The DB credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/var/www/html` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
