<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mazanoke

[MAZANOKE](https://github.com/civilblur/mazanoke) — a self-hosted, client-side image optimizer that compresses and converts images entirely in the browser. A `kurly.http` workload on the official image; all processing happens client-side, so the server only serves static assets and holds no data.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mazanoke = import 'github.com/metio/kurly/workloads/mazanoke/server.libsonnet';
kurly.list(mazanoke())
```

Stateless — a plain, horizontally scalable Deployment. Serves on `:80`. Images never leave the browser.
