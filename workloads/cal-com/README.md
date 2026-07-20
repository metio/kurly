<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# cal-com

[Cal.com](https://cal.com) — a self-hosted, open-source scheduling platform, an alternative to Calendly. A `kurly.http` workload on the official image, backed by an external PostgreSQL.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local calcom = import 'github.com/metio/kurly/workloads/cal-com/server.libsonnet';
kurly.list(calcom(webappUrl='https://cal.example.com'))
```

Stateless — a plain rolling Deployment. Serves on `:3000`.

**Secrets:** Cal.com reads `DATABASE_URL`, `NEXTAUTH_SECRET`, `CALENDSO_ENCRYPTION_KEY` and its integration credentials from the environment. kurly authors no Secret; provide one (via `secretName`) holding them. The defaults pair with a `cnpg-cluster` named `cal-com-db`.
