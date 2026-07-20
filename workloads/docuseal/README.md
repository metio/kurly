<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# docuseal

[DocuSeal](https://www.docuseal.com) — a self-hosted document-signing platform: build
fillable PDF forms and collect legally-binding e-signatures, an open alternative to
DocuSign. A plain composable `kurly.http` workload on the official image; with the default
SQLite backend its database and uploaded documents live on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local docuseal = import 'github.com/metio/kurly/workloads/docuseal/server.libsonnet';
kurly.list(docuseal())
```

Point DocuSeal at an external PostgreSQL (`DATABASE_URL`) to scale past the single SQLite
writer. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves
on `:3000`.
