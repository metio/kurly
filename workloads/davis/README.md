<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# davis

[Davis](https://github.com/tchapi/davis) — a self-hosted CalDAV and CardDAV server with a simple admin UI, built on sabre/dav. A `kurly.http` workload on the official image, backed by an external database (MySQL/MariaDB, PostgreSQL, or SQLite).

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local davis = import 'github.com/metio/kurly/workloads/davis/server.libsonnet';
kurly.list(davis())
```

Stateless — calendars and contacts live in the database, so a plain rolling Deployment. Serves the web UI and CalDAV/CardDAV endpoints on `:80`.

**Secrets:** Davis reads `DATABASE_URL`, `APP_SECRET` and the admin login from the environment. kurly authors no Secret; provide one (via `secretName`) holding them. Pair it with a database you run separately (e.g. a `cnpg-cluster` named `davis-db`).
