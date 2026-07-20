<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# minio

[MinIO](https://min.io) — a high-performance, self-hosted, S3-compatible object storage server. A `kurly.http` workload on the official image; objects on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local minio = import 'github.com/metio/kurly/workloads/minio/server.libsonnet';
kurly.list(minio())
```

Single-node MinIO. `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` come from a Secret via `envFrom` — kurly authors **no Secret**. The web console (`:9001`) needs an extra Service. Objects at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the S3 API on `:9000`.
