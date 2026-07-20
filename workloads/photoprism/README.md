<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# photoprism

[PhotoPrism](https://github.com/photoprism/photoprism) — an AI-powered, self-hosted
photo-management app with face recognition and automatic tagging. A plain composable
`kurly.http` workload on the official image: with the SQLite backend its database,
cache, and originals live on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local photoprism = import 'github.com/metio/kurly/workloads/photoprism/server.libsonnet';

kurly.list(photoprism(siteUrl='https://photos.example.com/'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `photoprism` | |
| `image` | `docker.io/photoprism/photoprism:260601` | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | database, cache (`/photoprism/storage`) and originals |
| `siteUrl` | inferred | the public URL (keep the trailing `/`) |
| `adminUser` | `admin` | the admin username |
| `secretName` | `photoprism-secrets` | Secret with `PHOTOPRISM_ADMIN_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:2342` — compose an exposure onto it.

## Security and persistence

The image runs its indexing (TensorFlow) and thumbnailer and writes across the root
filesystem, so this workload relaxes kurly's read-only-rootfs default while keeping
non-root, dropped capabilities, and no privilege escalation. The database, cache, and
originals live on a ReadWriteOnce volume, so this is **one replica, recreated**. Point
`PHOTOPRISM_DATABASE_DRIVER` at external MariaDB (the [mysql-cluster](../mysql-cluster/)
workload) to scale past the single SQLite writer.
