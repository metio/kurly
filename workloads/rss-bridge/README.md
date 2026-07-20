<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# rss-bridge

[RSS-Bridge](https://github.com/RSS-Bridge/rss-bridge) — generates RSS/Atom feeds for
sites that do not publish their own, from a large library of community "bridges". A plain
composable `kurly.http` workload on the official image. It holds no persistent state —
feeds are produced on request — so it is a plain **stateless** Deployment.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local rssBridge = import 'github.com/metio/kurly/workloads/rss-bridge/server.libsonnet';
kurly.list(rssBridge())
```

To restrict which bridges are enabled, mount a `whitelist.txt` over `/app/whitelist.txt`.
Serves on `:80`.
