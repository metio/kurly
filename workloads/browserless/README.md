<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# browserless

[Browserless](https://www.browserless.io) — a headless-Chromium service exposing a REST/WebSocket API for rendering, screenshots, PDF generation and scraping. A **stateless** `kurly.http` workload on the official image. The browser companion apps like [changedetection](../changedetection/) and [karakeep](../karakeep/) expect.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local browserless = import 'github.com/metio/kurly/workloads/browserless/server.libsonnet';
kurly.list(browserless())
```

`TOKEN` comes from a Secret via `envFrom` — kurly authors **no Secret**. Serves on `:3000`.
