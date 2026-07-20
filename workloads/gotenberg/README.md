<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gotenberg

[Gotenberg](https://gotenberg.dev) — a stateless API for converting HTML, Markdown and Office documents to PDF, powered by Chromium and LibreOffice. A **stateless** `kurly.http` workload on the official image. The PDF-conversion companion apps like [paperless-ngx](../paperless-ngx/) and [docuseal](../docuseal/) expect.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gotenberg = import 'github.com/metio/kurly/workloads/gotenberg/server.libsonnet';
kurly.list(gotenberg())
```

Serves on `:3000`.
