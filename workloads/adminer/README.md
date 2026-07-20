<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# adminer

[Adminer](https://www.adminer.org) — a full-featured database management tool in a single PHP file (MySQL, PostgreSQL, SQLite and more). A **stateless** `kurly.http` workload on the official image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local adminer = import 'github.com/metio/kurly/workloads/adminer/server.libsonnet';
kurly.list(adminer())
```

Serves on `:8080`.
