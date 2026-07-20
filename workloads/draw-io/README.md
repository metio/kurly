<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# draw-io

[draw.io / diagrams.net](https://www.drawio.com) — a self-hosted, client-side diagram editor. A `kurly.http` workload on the official image. The editor runs entirely in the browser; the server only serves static assets and a stateless export/proxy endpoint, so it holds no data.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local drawio = import 'github.com/metio/kurly/workloads/draw-io/server.libsonnet';
kurly.list(drawio())
```

Stateless — a plain, horizontally scalable Deployment. Serves on `:8080`. Diagrams are saved wherever the user chooses (browser, their own Drive/OneDrive/GitHub); the server keeps nothing.
