<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# linkstack

[LinkStack](https://linkstack.org) — a self-hosted, customizable "link in bio" page, a private alternative to Linktree. A `kurly.http` workload on the official image (pinned by digest — Renovate maintains it); with the default SQLite backend its data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local linkstack = import 'github.com/metio/kurly/workloads/linkstack/server.libsonnet';
kurly.list(linkstack())
```

Data at `/htdocs` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
