<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# xwiki

[XWiki](https://www.xwiki.org) — a powerful, self-hosted enterprise wiki and application-development platform: structured pages, macros, apps and fine-grained rights. A `kurly.http` workload on the official PostgreSQL/Tomcat image, backed by an external PostgreSQL, with its permanent directory on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local xwiki = import 'github.com/metio/kurly/workloads/xwiki/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(cnpg(name='xwiki-db', database='xwiki')).items,
  kurly.list(xwiki()).items,
]))
```

The `DB_*` connection comes from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/usr/local/xwiki` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8080`.
