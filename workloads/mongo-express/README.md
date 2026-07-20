<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mongo-express

[mongo-express](https://github.com/mongo-express/mongo-express) — a lightweight, web-based MongoDB admin UI. A **stateless** `kurly.http` workload on the official image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mongoExpress = import 'github.com/metio/kurly/workloads/mongo-express/server.libsonnet';
kurly.list(mongoExpress())
```

`ME_CONFIG_MONGODB_URL` and the basic-auth credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Serves on `:8081`.
