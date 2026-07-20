<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# nocodb

[NocoDB](https://github.com/nocodb/nocodb) — an open-source Airtable alternative that
turns any SQL database into a smart spreadsheet. A plain composable `kurly.http`
workload on the official image, backed by an external PostgreSQL for its metadata,
with attachments on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local nocodb = import 'github.com/metio/kurly/workloads/nocodb/server.libsonnet';

kurly.list(nocodb(publicUrl='https://nocodb.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `nocodb` | |
| `image` | `docker.io/nocodb/nocodb:2026.07.0` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | attachments (`/usr/app/data`) |
| `publicUrl` | inferred | the public URL |
| `secretName` | `nocodb-secrets` | Secret with `NC_DB` and `NC_AUTH_JWT_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:8080` — compose an exposure onto it.

## Database and secrets

NocoDB reads `NC_DB` (a connection string with the database password, point it at a
[cnpg-cluster](../cnpg-cluster/)) and `NC_AUTH_JWT_SECRET` from the environment. kurly
authors **no Secret** — provide `nocodb-secrets` holding both, pulled in via `envFrom`
(fill it with [`kurly.externalSecret`](../../main.libsonnet)).

## Persistence

Local attachments live on a ReadWriteOnce volume, so this is **one replica,
recreated**. Move attachments to S3 (the [seaweedfs](../seaweedfs/) workload) to scale
out.
