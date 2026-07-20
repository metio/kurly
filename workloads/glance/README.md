<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# glance

[Glance](https://github.com/glanceapp/glance) — a self-hosted dashboard that puts your feeds, RSS, weather, markets, monitoring and homelab widgets on one fast page. A `kurly.http` workload on the official image; its layout is a `glance.yml` mounted as a ConfigMap.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local glance = import 'github.com/metio/kurly/workloads/glance/server.libsonnet';
kurly.list(glance(config={ pages: [{ name: 'Home', columns: [{ size: 'full', widgets: [{ type: 'clock' }] }] }] }))
```

`config` is Glance's own `glance.yml`, mounted verbatim — kurly does not model it. Stateless — the default shows a minimal page. Serves on `:8080`.
