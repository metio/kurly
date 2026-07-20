<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# grist

[Grist](https://www.getgrist.com) — a self-hosted, open-source relational spreadsheet: the flexibility of a spreadsheet with the structure of a database, plus Python formulas and access rules. A `kurly.http` workload on the official image; documents (SQLite) on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local grist = import 'github.com/metio/kurly/workloads/grist/server.libsonnet';
kurly.list(grist())
```

Documents at `/persist` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8484`.
