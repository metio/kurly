<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# documenso

[Documenso](https://documenso.com) — a self-hosted, open-source alternative to DocuSign for signing documents. A `kurly.http` workload on the official image, backed by an external PostgreSQL.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local documenso = import 'github.com/metio/kurly/workloads/documenso/server.libsonnet';
kurly.list(documenso(webappUrl='https://sign.example.com'))
```

Stateless — a plain rolling Deployment. Serves on `:3000`.

**Secrets:** Documenso reads `NEXTAUTH_SECRET`, `NEXT_PRIVATE_ENCRYPTION_KEY`, `NEXT_PRIVATE_DATABASE_URL` and its SMTP settings from the environment. kurly authors no Secret; provide one (via `secretName`) holding them. The defaults pair with a `cnpg-cluster` named `documenso-db`.
