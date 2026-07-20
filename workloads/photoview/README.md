<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# photoview

[Photoview](https://photoview.github.io) — a self-hosted photo gallery for photographers: it
scans a media library, builds albums and serves them with face recognition and RAW support. A
`kurly.http` workload on the official image, backed by an external MySQL/MariaDB or PostgreSQL,
with **two PersistentVolumes** — the media library and a thumbnail cache.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local photoview = import 'github.com/metio/kurly/workloads/photoview/server.libsonnet';
local mysql = import 'github.com/metio/kurly/workloads/mysql-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(mysql(name='photoview-db')).items,
  kurly.list(photoview()).items,
]))
```

Photoview keeps two directories on disk — the media library at `/photos` (add photos there to
scan) and the cache at `/app/cache` — so the workload composes `kurly.store` **twice**, one PVC
each (sized by `mediaSize`/`cacheSize`). The database driver and connection
(`PHOTOVIEW_DATABASE_DRIVER`, `PHOTOVIEW_MYSQL_URL` / `PHOTOVIEW_POSTGRES_URL`) come from a Secret
via `envFrom` — kurly authors **no Secret**. Both volumes are ReadWriteOnce, so this is **one
replica, recreated**. Serves on `:80`.
