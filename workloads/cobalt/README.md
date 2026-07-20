<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# cobalt

[cobalt](https://github.com/imputnet/cobalt) — a self-hosted media-downloader backend: give it a link and it returns a clean download for supported sites. A `kurly.http` workload on the official image. The API is stateless — it streams and re-muxes on demand and keeps nothing.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local cobalt = import 'github.com/metio/kurly/workloads/cobalt/server.libsonnet';
kurly.list(cobalt(apiUrl='https://cobalt-api.example.com'))
```

Stateless — a plain, horizontally scalable Deployment. Serves the API on `:9000`. This is the API only; run a cobalt web frontend separately if you want the UI.

**Configuration:** cobalt reads `API_URL` (its own public URL, required) and optional tuning/auth settings from the environment. Provide any secret tokens through a Secret (compose `kurly.envFromSecret` on).
