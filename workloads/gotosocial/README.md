<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gotosocial

[GoToSocial](https://gotosocial.org) — a lightweight, self-hosted ActivityPub/Fediverse
social server, an alternative to Mastodon that federates with it. A plain composable
`kurly.http` workload on the official image; with the default SQLite backend its database
and stored media live on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gotosocial = import 'github.com/metio/kurly/workloads/gotosocial/server.libsonnet';
kurly.list(gotosocial(host='social.example.com'))
```

The `host` (the domain in every account's `@handle`) is **fixed at first run and cannot be
changed later** — set it deliberately. Point GoToSocial at an external PostgreSQL
(`GTS_DB_TYPE=postgres` plus the `GTS_DB_*` connection) to scale past SQLite. Data at
`/gotosocial/storage` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on
`:8080`.
