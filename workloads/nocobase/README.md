<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# nocobase

[NocoBase](https://www.nocobase.com) — a self-hosted, open-source no-code/low-code platform for building internal tools, databases and workflows. A `kurly.http` workload on the official image, backed by an external PostgreSQL, with storage on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local nocobase = import 'github.com/metio/kurly/workloads/nocobase/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(cnpg(name='nocobase-db', database='nocobase')).items,
  kurly.list(nocobase()).items,
]))
```

The `DB_*` connection and `APP_KEY` come from a Secret via `envFrom` — kurly authors **no Secret**. Storage at `/app/nocobase/storage` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
