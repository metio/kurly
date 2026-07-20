<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# baserow

[Baserow](https://baserow.io/) — an open-source, no-code database and Airtable
alternative. A plain composable `kurly.http` workload on the official **all-in-one**
image, which bundles the backend, the web frontend, Celery workers, and (by default)
an embedded PostgreSQL and Redis — everything in `/baserow/data` on a PersistentVolume,
so a single instance needs nothing external.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local baserow = import 'github.com/metio/kurly/workloads/baserow/server.libsonnet';

kurly.list(baserow(publicUrl='https://baserow.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `baserow` | |
| `image` | `docker.io/baserow/baserow:2.3.2` | the all-in-one image |
| `storageSize` / `storageClass` | `10Gi` / cluster default | everything (`/baserow/data`) |
| `publicUrl` | inferred | the public URL |
| `secretName` | `baserow-secrets` | Secret with `BASEROW_SECRET_KEY`, `BASEROW_JWT_SIGNING_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:80` — compose an exposure onto it. Point `DATABASE_*`
/ `REDIS_*` at external services (a [cnpg-cluster](../cnpg-cluster/) and
[valkey](../valkey/)) through `env` to scale past the embedded single instance.

## Security and persistence

The all-in-one image supervises multiple processes (including the embedded database)
and writes across the root filesystem, so this workload relaxes kurly's non-root and
read-only-rootfs defaults while keeping dropped capabilities and no privilege
escalation. Everything lives on a ReadWriteOnce volume, so this is **one replica,
recreated**.
