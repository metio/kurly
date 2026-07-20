<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# lemmy

[Lemmy](https://join-lemmy.org) — a self-hosted, open-source link aggregator and forum for the
Fediverse, a Reddit alternative. It runs as **three workloads** — a `backend` (API + federation),
a `ui` (web frontend), and `pictrs` (image storage) — backed by an external PostgreSQL.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local backend = import 'github.com/metio/kurly/workloads/lemmy/backend.libsonnet';
local ui = import 'github.com/metio/kurly/workloads/lemmy/ui.libsonnet';
local pictrs = import 'github.com/metio/kurly/workloads/lemmy/pictrs.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='lemmy-db', database='lemmy')).items,
  kurly.list(backend()).items,
  kurly.list(ui(externalHost='lemmy.example.com')).items,
  kurly.list(pictrs()).items,
]))
```

The **backend** reads its config (with the PostgreSQL connection and the pict-rs API key) from
`/config/config.hjson`, mounted from an **existing Secret** you provide (`lemmy-config`) — kurly
never mints key material. The **ui** is the user-facing stage on `:1234` and reaches the backend
by its Service name. **pictrs** serves images on `:8080` with them stored on a ReadWriteOnce
volume (one replica, recreated), authenticated by an API key from its own Secret.
