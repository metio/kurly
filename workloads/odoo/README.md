<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# odoo

[Odoo](https://www.odoo.com) — a self-hosted, all-in-one business/ERP suite: CRM, sales, inventory, accounting, website and more. A `kurly.http` workload on the official image, backed by an external PostgreSQL, with its filestore on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local odoo = import 'github.com/metio/kurly/workloads/odoo/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(cnpg(name='odoo-db', database='odoo')).items,
  kurly.list(odoo()).items,
]))
```

The PostgreSQL connection (`HOST`/`USER`/`PASSWORD`) comes from a Secret via `envFrom` — kurly authors **no Secret**. Filestore at `/var/lib/odoo` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8069`.
