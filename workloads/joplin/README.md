<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# joplin

[Joplin Server](https://github.com/laurent22/joplin) — the self-hosted sync target for the Joplin note-taking apps. A `kurly.http` workload on the official image, backed by an external PostgreSQL.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local joplin = import 'github.com/metio/kurly/workloads/joplin/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(cnpg(name='joplin-db', database='joplin')).items,
  kurly.list(joplin(appBaseUrl='https://joplin.example.com')).items,
]))
```

The `POSTGRES_*` connection comes from a Secret via `envFrom` — kurly authors **no Secret**. Stateless (notes live in PostgreSQL). Serves on `:22300`.
