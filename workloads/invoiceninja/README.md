<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# invoiceninja

[Invoice Ninja](https://github.com/invoiceninja/invoiceninja) — self-hosted
invoicing, quotes, and payments. A plain composable `kurly.http` workload on the
official image, backed by an external MySQL/MariaDB, with its uploads and generated
PDFs on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local invoiceninja = import 'github.com/metio/kurly/workloads/invoiceninja/server.libsonnet';

kurly.list(invoiceninja(appUrl='https://invoicing.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `invoiceninja` | |
| `image` | `docker.io/invoiceninja/invoiceninja:5.13.26` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | uploads and PDFs (`/var/www/html/storage`) |
| `dbHost` / `dbName` / `dbUser` | `invoiceninja-db` / `invoiceninja` / `invoiceninja` | the MySQL/MariaDB database |
| `appUrl` | inferred | the public URL |
| `secretName` | `invoiceninja-secrets` | Secret with `DB_PASSWORD` and `APP_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:80` — compose an exposure onto it.

## Database and secrets

Invoice Ninja needs a **MySQL/MariaDB** database. kurly ships no MySQL recipe —
bring your own (an operator-managed instance, or one you run) and point `dbHost` at
it. It reads `DB_HOST`, `DB_DATABASE`, `DB_USERNAME` from env and `DB_PASSWORD` and
`APP_KEY` from a provided Secret via `envFrom`. kurly authors **no Secret** — fill
`invoiceninja-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The nginx + PHP-FPM image starts as **root** and binds `:80`, so this workload
relaxes kurly's non-root and read-only-rootfs defaults while keeping dropped
capabilities and no privilege escalation. Uploads and PDFs live on a ReadWriteOnce
volume, so this is **one replica, recreated**. A separate queue worker (for emails
and background jobs) can be added by composing a second deployment running
`php artisan queue:work`.
