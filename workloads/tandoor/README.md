<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# tandoor

[Tandoor Recipes](https://tandoor.dev) — a self-hosted recipe manager and meal planner with a smart shopping list. A `kurly.http` workload on the official image, backed by an external PostgreSQL; uploaded media on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local tandoor = import 'github.com/metio/kurly/workloads/tandoor/server.libsonnet';
kurly.list(tandoor())
```

Media at `/opt/recipes/mediafiles` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8080`.

**Secrets:** Tandoor reads `SECRET_KEY` and its PostgreSQL settings from the environment. kurly authors no Secret; provide one (via `secretName`) holding them. The defaults pair with a `cnpg-cluster` named `tandoor-db`.
