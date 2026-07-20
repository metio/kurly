<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# searxng

[SearXNG](https://github.com/searxng/searxng) — a privacy-respecting, self-hosted
metasearch engine that aggregates results from many search services without tracking you. A
plain composable `kurly.http` workload on the official image; its behaviour is its
`settings.yml`, mounted as a ConfigMap, and it keeps no persistent state of its own.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local searxng = import 'github.com/metio/kurly/workloads/searxng/server.libsonnet';
kurly.list(searxng(baseUrl='https://search.example.com'))
```

`settings` is SearXNG's own `settings.yml`, mounted verbatim — kurly does not model it. Set
`SEARXNG_SECRET` from a Secret via `envFrom` (it overrides `server.secret_key` at runtime);
kurly authors **no Secret**. A busy instance also wants a [Valkey](../valkey/) for the
limiter (`settings.redis.url`). Stateless — scale freely. Serves on `:8080`.
