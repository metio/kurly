<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# whoogle

[Whoogle Search](https://github.com/benbusby/whoogle-search) — a self-hosted, privacy-respecting metasearch proxy for Google results: no ads, no tracking, no JavaScript required. A **stateless** `kurly.http` workload on the official image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local whoogle = import 'github.com/metio/kurly/workloads/whoogle/server.libsonnet';
kurly.list(whoogle())
```

Configure through `WHOOGLE_CONFIG_*` env vars. Serves on `:5000`.
