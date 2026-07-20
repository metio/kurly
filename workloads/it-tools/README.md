<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# it-tools

[IT-Tools](https://github.com/CorentinTh/it-tools) — a large collection of handy online
tools for developers and sysadmins (encoders, converters, generators, formatters), all
client-side. A plain composable `kurly.http` workload on the official image; it serves a
static app and keeps no state, so it is a plain **stateless** Deployment.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local itTools = import 'github.com/metio/kurly/workloads/it-tools/server.libsonnet';
kurly.list(itTools())
```

Serves on `:80`.
