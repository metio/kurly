<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# drawio

[draw.io / diagrams.net](https://github.com/jgraph/drawio) — the self-hosted web editor
for flowcharts, UML and network diagrams. A plain composable `kurly.http` workload on the
official image; the editor runs in the browser and stores diagrams wherever the user
chooses, so the server is **stateless**.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local drawio = import 'github.com/metio/kurly/workloads/drawio/server.libsonnet';
kurly.list(drawio())
```

Serves the editor on `:8080`.
