<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# vikunja

[Vikunja](https://vikunja.io/) — a self-hosted to-do and project-management app. A
plain composable `kurly.http` workload on the official all-in-one image: it keeps its
data in a SQLite database and its file attachments on a PersistentVolume by default,
so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local vikunja = import 'github.com/metio/kurly/workloads/vikunja/server.libsonnet';

kurly.list(vikunja(publicUrl='https://tasks.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `vikunja` | |
| `image` | `docker.io/vikunja/vikunja:v2.4.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | database (`/db`) and attachments (`/files`) |
| `publicUrl` | inferred | the public URL |
| `secretName` | `vikunja-secrets` | Secret with `VIKUNJA_SERVICE_JWTSECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:3456` — compose an exposure onto it. Point
`VIKUNJA_DATABASE_TYPE` at an external PostgreSQL/MySQL through `env` to scale past the
single SQLite writer.

## Secrets and persistence

Vikunja reads `VIKUNJA_SERVICE_JWTSECRET` from the environment (keep it stable —
sessions depend on it). kurly authors **no Secret** — provide `vikunja-secrets`
holding it, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The SQLite database and attachments
live on a ReadWriteOnce volume, so this is **one replica, recreated**.
